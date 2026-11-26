defmodule Colony.World do
  @moduledoc """
  The state of the world and the rules that change it.

  This module has no processes and no clock. `tick/2` moves the world one step. The server
  process calls it 10 times each second. The tests call it as fast as possible.

  Each change that a client must know is added to `events`. `tick/2` returns the events of
  the step and removes them from the world.
  """

  alias Colony.{Grid, Support, Workers}

  defstruct cfg: nil,
            p: nil,
            grid: nil,
            rule: nil,
            seed: 0,
            rng: nil,
            tick: 0,
            now: 0,
            # Free workers: id => %{cell, carry, mode}.
            workers: %{},
            worker_count: 0,
            # Locked bodies: cell => %{kind, id, name, time}.
            locked: %{},
            # Support of the locked bodies: cell => support.
            supports: %{},
            # The last tick when a free body was on a locked body: cell => tick.
            used: %{},
            # Scent: cell => 1..100.
            scent: %{},
            food_pile: 0,
            food_nest: 0,
            food_empty_tick: nil,
            # Players: id => player.
            players: %{},
            next_player: 1,
            # The empty gap cells where a lock is possible.
            frontier: [],
            # The number of steps on foot from each cell to the nest.
            walk: %{},
            walk_dirty: true,
            # The cells that are near scent or near the nest: cell => distance.
            leash: %{},
            demo: false,
            demo_front: 0.0,
            events: nil

  @empty_events %{
    moves: [],
    worker_set: [],
    worker_gone: [],
    locks: [],
    let_go: [],
    fell: [],
    scent: %{},
    names: [],
    you: [],
    structure: false,
    food: false
  }

  # A player can keep this many cells of movement for later. It absorbs late messages.
  # It is less than the distance to a cell that does not touch the cell of the body
  # (1.73): one move cannot go across a cell.
  @budget_cap 1.5
  # The world looks at points along the way of a move, this far apart.
  @way_step 0.25
  # A point of the way can be this far into a cell where a body cannot be. A body that
  # goes around a corner between two messages does this.
  @way_margin [{0.2, 0.0}, {-0.2, 0.0}, {0.1, 0.173}, {-0.1, 0.173}, {0.1, -0.173}, {-0.1, -0.173}]
  # A player touches the food from this distance.
  @food_touch 1.3

  @doc """
  Makes a world from the game config.

  `saved` is the term from `to_save/1`, or nil for a new world.
  """
  def new(cfg, saved \\ nil) do
    grid = Grid.new(cfg)
    rate = Keyword.fetch!(cfg, :tick_rate)
    seed = (saved && saved.seed) || Keyword.get(cfg, :seed) || :rand.uniform(0x7FFFFFFF)

    refill = Keyword.get(cfg, :food_refill_seconds)
    {nest_row, nest_col} = Keyword.fetch!(cfg, :nest)

    p = %{
      rate: rate,
      step: Keyword.fetch!(cfg, :speed) / rate,
      leash: Keyword.fetch!(cfg, :leash),
      food_radius: Keyword.fetch!(cfg, :food_radius),
      food_units: Keyword.fetch!(cfg, :food_units),
      refill_ticks: refill && refill * rate,
      let_go_ticks: Keyword.fetch!(cfg, :let_go_seconds) * rate,
      respawn_ticks: Keyword.fetch!(cfg, :respawn_seconds) * rate,
      scent_max: Keyword.fetch!(cfg, :scent_max),
      scent_player: Keyword.fetch!(cfg, :scent_player),
      scent_carry: Keyword.fetch!(cfg, :scent_carry),
      decay_ticks: Keyword.fetch!(cfg, :scent_decay_seconds) * rate,
      gap_cells: for(cell <- 0..(grid.count - 1), Grid.kind(grid, cell) == :gap, do: cell),
      # The demo mode puts scent on these cells: from the nest to the gap in a straight line.
      demo_path: for(row <- nest_row..Grid.near_edge_row(grid), do: Grid.cell(grid, row, nest_col))
    }

    world = %__MODULE__{
      cfg: cfg,
      p: p,
      grid: grid,
      rule: Support.rule(cfg),
      seed: seed,
      rng: :rand.seed_s(:exsss, seed),
      worker_count: Keyword.fetch!(cfg, :workers),
      food_pile: p.food_units,
      events: @empty_events
    }

    world
    |> restore(saved)
    |> place_workers()
    |> refresh_structure()
    |> refresh_walk()
    |> refresh_leash()
  end

  # ---------------------------------------------------------------------------
  # Save and load

  @doc "The part of the world that goes into the save file."
  def to_save(%__MODULE__{} = world) do
    %{
      version: 1,
      seed: world.seed,
      locked:
        world.locked
        |> Enum.map(fn {cell, body} -> {cell, body.kind, body.name, body.time} end)
        |> Enum.sort(),
      scent: world.scent,
      food_pile: world.food_pile,
      food_nest: world.food_nest
    }
  end

  defp restore(world, nil), do: world

  defp restore(world, %{version: 1} = saved) do
    # A saved cell is used only if it is a gap cell of this grid. The config can change
    # between two runs.
    {locked, _} =
      saved.locked
      |> Enum.filter(fn {cell, _, _, _} ->
        cell < world.grid.count and Grid.kind(world.grid, cell) == :gap
      end)
      |> Enum.reduce({%{}, 0}, fn
        {cell, :worker, _name, time}, {locked, next} when next < world.worker_count ->
          {Map.put(locked, cell, %{kind: :worker, id: next, name: "", time: time}), next + 1}

        {_cell, :worker, _name, _time}, acc ->
          acc

        {cell, :player, name, time}, {locked, next} ->
          {Map.put(locked, cell, %{kind: :player, id: 0, name: name, time: time}), next}
      end)

    scent = Map.filter(saved.scent, fn {cell, _} -> cell < world.grid.count end)

    %{
      world
      | locked: locked,
        used: Map.new(locked, fn {cell, _} -> {cell, 0} end),
        scent: scent,
        food_pile: saved.food_pile,
        food_nest: saved.food_nest,
        food_empty_tick: if(saved.food_pile == 0, do: 0)
    }
  end

  # The workers that are not locked start near the nest.
  defp place_workers(world) do
    grid = world.grid
    taken = for {_, %{kind: :worker, id: id}} <- world.locked, into: MapSet.new(), do: id

    spots =
      for cell <- 0..(grid.count - 1),
          Grid.kind(grid, cell) == :near,
          Grid.nest_distance(grid, cell) <= 3,
          do: cell

    spots = List.to_tuple(spots)

    Enum.reduce(0..(world.worker_count - 1)//1, world, fn id, world ->
      if MapSet.member?(taken, id) do
        world
      else
        {n, rng} = :rand.uniform_s(tuple_size(spots), world.rng)
        worker = %{cell: elem(spots, n - 1), carry: false, mode: :out}
        %{world | rng: rng, workers: Map.put(world.workers, id, worker)}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Players

  @doc "Adds a player. The player gets a body at the nest. Returns `{world, id}`."
  def join(%__MODULE__{} = world, name) do
    id = free_player_id(world, world.next_player)
    {x, z} = Grid.center(world.grid, world.grid.nest)

    player = %{
      name: name,
      x: x,
      z: z,
      heading: 0.0,
      scent: false,
      cell: world.grid.nest,
      state: :alive,
      budget: @budget_cap,
      touched_food: false
    }

    world = %{
      world
      | players: Map.put(world.players, id, player),
        next_player: rem(id, 0xFFFE) + 1
    }

    {event(world, :names, {id, name}), id}
  end

  defp free_player_id(world, id) do
    if is_map_key(world.players, id), do: free_player_id(world, rem(id, 0xFFFE) + 1), else: id
  end

  @doc "Removes a player. The locked bodies of the player stay."
  def leave(%__MODULE__{} = world, id) do
    %{world | players: Map.delete(world.players, id)}
  end

  @doc """
  A player tells where the body is now.

  The world accepts the position only if the body can be there: the cell is a bank cell or
  a locked body, the distance is not more than the speed permits, and the straight way to
  the position does not go across a cell where a body cannot be. If not, the body stays
  where it was and the player gets the correct position.
  """
  def move(%__MODULE__{} = world, id, x, z, heading, scent?) do
    case world.players do
      %{^id => %{state: :alive} = player} ->
        distance = :math.sqrt((x - player.x) ** 2 + (z - player.z) ** 2)
        cell = Grid.cell_at(world.grid, x, z)
        player = %{player | heading: heading, scent: scent?}

        if cell != nil and walkable?(world, cell) and distance <= player.budget + 0.05 and
             clear_way?(world, player.x, player.z, x, z, distance) do
          player = %{player | x: x, z: z, cell: cell, budget: max(0.0, player.budget - distance)}
          %{world | players: Map.put(world.players, id, player)}
        else
          %{world | players: Map.put(world.players, id, player)}
          |> event(:you, {id, %{x: player.x, z: player.z}})
        end

      _ ->
        world
    end
  end

  @doc """
  A player locks the body into a cell.

  Returns `{:ok, world}` or `{{:error, reason}, world}`.
  """
  def lock(%__MODULE__{} = world, id, cell) do
    with %{state: :alive} = player <- Map.get(world.players, id),
         true <- is_integer(cell) and cell >= 0 and cell < world.grid.count,
         true <- cell in Grid.neighbors(world.grid, player.cell),
         true <- can_lock?(world, cell) do
      body = %{kind: :player, id: id, name: player.name, time: world.now}

      world =
        world
        |> kill_player(id, player, "lock")
        |> put_lock(cell, body)

      {:ok, world}
    else
      _ -> {{:error, :not_possible}, world}
    end
  end

  # True if each point along the straight way is on a cell where a body can be, or very
  # near to such a cell.
  defp clear_way?(world, x0, z0, x1, z1, distance) do
    steps = ceil(distance / @way_step)

    Enum.all?(1..(steps - 1)//1, fn step ->
      part = step / steps
      x = x0 + (x1 - x0) * part
      z = z0 + (z1 - z0) * part

      ground?(world, x, z) or
        Enum.any?(@way_margin, fn {dx, dz} -> ground?(world, x + dx, z + dz) end)
    end)
  end

  defp ground?(world, x, z) do
    cell = Grid.cell_at(world.grid, x, z)
    cell != nil and walkable?(world, cell)
  end

  defp kill_player(world, id, player, reason) do
    player = %{player | state: {:dead, world.tick + world.p.respawn_ticks}, scent: false}

    %{world | players: Map.put(world.players, id, player)}
    |> event(:you, {id, %{state: "dead", reason: reason}})
  end

  @doc "Starts or stops the scent of the demo mode."
  def set_demo(%__MODULE__{} = world, demo?) do
    %{world | demo: demo?, demo_front: if(demo?, do: world.demo_front, else: 0.0)}
  end

  # ---------------------------------------------------------------------------
  # Queries

  @doc "True if a free body can be on the cell."
  def walkable?(world, cell) do
    Grid.kind(world.grid, cell) != :gap or is_map_key(world.locked, cell)
  end

  @doc "True if a body can lock into the cell now."
  def can_lock?(world, cell) do
    Support.can_lock?(world.grid, world.rule, world.locked, world.supports, cell)
  end

  @doc "The scent of a cell."
  def scent(world, cell), do: Map.get(world.scent, cell, 0)

  # ---------------------------------------------------------------------------
  # Changes that the worker rules also use

  @doc false
  def event(world, key, item) do
    events = world.events
    %{world | events: %{events | key => [item | Map.fetch!(events, key)]}}
  end

  @doc false
  def flag(world, key), do: %{world | events: %{world.events | key => true}}

  @doc false
  def put_scent(world, cell, value) do
    if Map.get(world.scent, cell, 0) == value do
      world
    else
      events = world.events

      %{
        world
        | scent: Map.put(world.scent, cell, value),
          events: %{events | scent: Map.put(events.scent, cell, value)}
      }
    end
  end

  @doc false
  def add_scent(world, cell, amount) do
    put_scent(world, cell, min(world.p.scent_max, Map.get(world.scent, cell, 0) + amount))
  end

  @doc false
  def take_food(world) do
    pile = world.food_pile - 1

    %{world | food_pile: pile, food_empty_tick: if(pile == 0, do: world.tick)}
    |> flag(:food)
  end

  @doc false
  def add_nest_food(world) do
    flag(%{world | food_nest: world.food_nest + 1}, :food)
  end

  @doc false
  def touch(world, cell) do
    if is_map_key(world.locked, cell) do
      %{world | used: Map.put(world.used, cell, world.tick)}
    else
      world
    end
  end

  @doc false
  # Puts a body into a gap cell. The caller makes sure that the lock is possible.
  def put_lock(world, cell, body) do
    locked = Map.put(world.locked, cell, body)

    %{
      world
      | locked: locked,
        supports: Support.calculate(world.grid, world.rule, locked),
        used: Map.put(world.used, cell, world.tick),
        walk_dirty: true
    }
    |> event(:locks, {cell, body})
    |> flag(:structure)
  end

  # ---------------------------------------------------------------------------
  # The step

  @doc """
  Moves the world one tick.

  `now` is the time in seconds. It goes into the locked bodies. With nil, the time is the
  number of seconds of world time.

  Returns `{world, events}`.
  """
  def tick(%__MODULE__{} = world, now \\ nil) do
    tick = world.tick + 1
    world = %{world | tick: tick, now: now || div(tick, world.p.rate)}

    world
    |> each_second()
    |> demo_scent()
    |> step_players()
    |> refresh_walk()
    |> Workers.step()
    |> take_events()
  end

  @doc "Returns `{world, events}` and removes the events from the world."
  def take_events(%__MODULE__{} = world) do
    world = if world.events.structure, do: refresh_frontier(world), else: world
    {%{world | events: @empty_events}, world.events}
  end

  defp each_second(world) do
    if rem(world.tick, world.p.rate) == 0 do
      world
      |> decay_scent()
      |> refill_food()
      |> let_go()
      |> refresh_leash()
    else
      world
    end
  end

  # The clients do the same subtraction at the same tick. Thus this change makes no event.
  defp decay_scent(world) do
    if rem(world.tick, world.p.decay_ticks) == 0 do
      scent = for {cell, value} <- world.scent, value > 1, into: %{}, do: {cell, value - 1}
      %{world | scent: scent}
    else
      world
    end
  end

  defp refill_food(%{food_pile: 0, food_empty_tick: empty, p: %{refill_ticks: ticks}} = world)
       when is_integer(empty) and is_integer(ticks) do
    if world.tick - empty >= ticks do
      flag(%{world | food_pile: world.p.food_units, food_empty_tick: nil}, :food)
    else
      world
    end
  end

  defp refill_food(world), do: world

  defp demo_scent(%{demo: true} = world) do
    path = world.p.demo_path
    front = min(length(path) * 1.0, world.demo_front + world.p.step)

    path
    |> Enum.take(trunc(front) + 1)
    |> Enum.reduce(%{world | demo_front: front}, &put_scent(&2, &1, world.p.scent_player))
  end

  defp demo_scent(world), do: world

  defp step_players(world) do
    Enum.reduce(world.players, world, fn
      {id, %{state: {:dead, at}} = player}, world when world.tick >= at ->
        {x, z} = Grid.center(world.grid, world.grid.nest)

        player = %{
          player
          | state: :alive,
            x: x,
            z: z,
            cell: world.grid.nest,
            budget: @budget_cap,
            scent: false
        }

        %{world | players: Map.put(world.players, id, player)}
        |> event(:you, {id, %{state: "alive", x: x, z: z}})

      {id, %{state: :alive} = player}, world ->
        # The 1.15 lets a client clock be a small quantity faster than the server clock.
        budget = min(@budget_cap, player.budget + world.p.step * 1.15)
        world = %{world | players: Map.put(world.players, id, %{player | budget: budget})}
        world = touch(world, player.cell)

        world =
          if player.scent, do: put_scent(world, player.cell, world.p.scent_player), else: world

        touch_food(world, id, %{player | budget: budget})

      _, world ->
        world
    end)
  end

  defp touch_food(world, _id, %{touched_food: true}), do: world

  defp touch_food(world, id, player) do
    {fx, fz} = Grid.center(world.grid, world.grid.food)

    if (player.x - fx) ** 2 + (player.z - fz) ** 2 <= @food_touch ** 2 do
      %{world | players: Map.put(world.players, id, %{player | touched_food: true})}
      |> event(:you, {id, %{food: true}})
    else
      world
    end
  end

  # ---------------------------------------------------------------------------
  # Let go and fall

  # A locked worker lets go when no free body was on it, or on a body that it touches,
  # for the let-go time.
  defp let_go(world) do
    world = touch_all(world)
    limit = world.tick - world.p.let_go_ticks

    idle =
      for {cell, %{kind: :worker} = body} <- world.locked, last_use(world, cell) <= limit do
        {cell, body}
      end

    if idle == [], do: world, else: remove(world, idle)
  end

  defp touch_all(world) do
    world =
      Enum.reduce(world.workers, world, fn {_id, worker}, world -> touch(world, worker.cell) end)

    Enum.reduce(world.players, world, fn
      {_id, %{state: :alive, cell: cell}}, world -> touch(world, cell)
      _, world -> world
    end)
  end

  defp last_use(world, cell) do
    Enum.reduce(Grid.neighbors(world.grid, cell), Map.get(world.used, cell, 0), fn next, last ->
      max(last, Map.get(world.used, next, 0))
    end)
  end

  @doc false
  # Takes bodies out of the bridge. `released` is a list of `{cell, body}`.
  # Then the bodies that have no support fall, and the free bodies that were on them fall.
  def remove(world, released) do
    released_cells = Enum.map(released, &elem(&1, 0))
    # The clients do not get this event: they get the structure. The contract tests use it.
    world = Enum.reduce(released_cells, world, &event(&2, :let_go, &1))
    locked = Map.drop(world.locked, released_cells)
    {supports, fallen} = Support.settle(world.grid, world.rule, locked)
    fallen_bodies = Map.take(locked, fallen)
    gone = released_cells ++ fallen

    world = %{
      world
      | locked: Map.drop(locked, fallen),
        supports: supports,
        used: Map.drop(world.used, gone),
        walk_dirty: true
    }

    # A worker that falls starts again at the nest.
    world =
      Enum.reduce(fallen_bodies, world, fn {cell, body}, world ->
        world = event(world, :fell, cell)
        if body.kind == :worker, do: free_worker(world, body.id, world.grid.nest, 2), else: world
      end)

    # A worker that lets go steps to a cell that touches it. If there is no such cell, it falls.
    world =
      Enum.reduce(released, world, fn {cell, body}, world ->
        case step_off(world, cell) do
          nil -> world |> event(:fell, cell) |> free_worker(body.id, world.grid.nest, 2)
          to -> free_worker(world, body.id, to, 0)
        end
      end)

    world
    |> drop_free_bodies(MapSet.new(gone))
    |> flag(:structure)
  end

  defp step_off(world, cell) do
    {bank, bodies} =
      world.grid
      |> Grid.neighbors(cell)
      |> Enum.filter(&walkable?(world, &1))
      |> Enum.split_with(&(Grid.kind(world.grid, &1) != :gap))

    case {bank, bodies} do
      {[to | _], _} -> to
      {[], []} -> nil
      {[], bodies} -> Enum.max_by(bodies, &Map.get(world.supports, &1, 0.0))
    end
  end

  # Flags of a worker for the clients: 1 = carries food, 2 = starts at a new position.
  defp free_worker(world, id, cell, flags) do
    worker = %{cell: cell, carry: false, mode: :out}

    %{world | workers: Map.put(world.workers, id, worker)}
    |> event(:worker_set, {id, cell, flags})
  end

  defp drop_free_bodies(world, gone) do
    world =
      Enum.reduce(world.workers, world, fn {id, worker}, world ->
        if MapSet.member?(gone, worker.cell) and not is_map_key(world.locked, worker.cell) do
          free_worker(world, id, world.grid.nest, 2)
        else
          world
        end
      end)

    Enum.reduce(world.players, world, fn
      {id, %{state: :alive, cell: cell} = player}, world ->
        if MapSet.member?(gone, cell) and not is_map_key(world.locked, cell) do
          kill_player(world, id, player, "fell")
        else
          world
        end

      _, world ->
        world
    end)
  end

  # ---------------------------------------------------------------------------
  # Values that are calculated from the state

  defp refresh_structure(world) do
    {supports, fallen} = Support.settle(world.grid, world.rule, world.locked)

    %{world | locked: Map.drop(world.locked, fallen), supports: supports, walk_dirty: true}
    |> refresh_frontier()
  end

  defp refresh_frontier(world) do
    %{world | frontier: Enum.filter(world.p.gap_cells, &can_lock?(world, &1))}
  end

  # The number of steps on foot to the nest, for each cell that has a way to the nest.
  defp refresh_walk(%{walk_dirty: false} = world), do: world

  defp refresh_walk(world) do
    nest = world.grid.nest
    walk = flood(world.grid, [nest], %{nest => 0}, 1, :infinity, &walkable?(world, &1))
    %{world | walk: walk, walk_dirty: false}
  end

  # The cells that are not more than `leash` cells from scent or from the nest.
  defp refresh_leash(world) do
    sources = [world.grid.nest | Map.keys(world.scent)]
    start = Map.new(sources, &{&1, 0})
    %{world | leash: flood(world.grid, sources, start, 1, world.p.leash, fn _ -> true end)}
  end

  defp flood(_grid, [], distances, _distance, _limit, _open?), do: distances

  defp flood(_grid, _front, distances, distance, limit, _open?) when distance > limit,
    do: distances

  defp flood(grid, front, distances, distance, limit, open?) do
    {next, distances} =
      Enum.reduce(front, {[], distances}, fn cell, acc ->
        Enum.reduce(Grid.neighbors(grid, cell), acc, fn to, {next, distances} = acc ->
          if is_map_key(distances, to) or not open?.(to) do
            acc
          else
            {[to | next], Map.put(distances, to, distance)}
          end
        end)
      end)

    flood(grid, next, distances, distance + 1, limit, open?)
  end
end
