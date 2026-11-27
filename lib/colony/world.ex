defmodule Colony.World do
  @moduledoc """
  The state of the world and the rules that change it.

  This module has no processes and no clock. `tick/2` moves the world one step. The server
  process calls it 10 times each second. The tests call it as fast as possible.

  Each change that a client must know is added to `events`. `tick/2` returns the events of
  the step and removes them from the world.

  The rules of plan 0003:

  - The world has rivers, one after the other. The colony builds one bridge for each river.
  - Only a player or a helper locks, and only into an open cell. A worker never locks.
  - A lock uses one spare body: the player takes the body of the nearest worker.
  - A crossing is the moment when a bridge touches the next land. It makes a record, and
    the next pile appears.
  - The world is complete when the first food of the last pile gets to the nest.
  """

  alias Colony.{Grid, Helpers, Support, Workers}

  defstruct cfg: nil,
            p: nil,
            grid: nil,
            rule: nil,
            seed: 0,
            rng: nil,
            tick: 0,
            now: 0,
            # The time of the first tick of the world.
            start: nil,
            # Workers: id => %{cell, carry, mode}. Each worker is a spare body. The mode is
            # :idle, :food, :wait, or {:fetch, pile} for a worker that goes to a new pile.
            workers: %{},
            # Worker numbers that are free for a new worker.
            free_ids: [],
            # Worker numbers that are free from the next tick. A client gets "worker gone"
            # and "worker set" of one number in two different messages.
            freed_ids: [],
            next_worker: 0,
            # Locked bodies: cell => %{name, helper, time, n, crossings}. `n` is the number
            # of the lock in the story, from 1.
            locked: %{},
            # Support of the locked bodies: cell => support, as an integer.
            supports: %{},
            lock_count: 0,
            # Scent: cell => 1..100. It is a picture of the road. No rule reads it.
            scent: %{},
            # The piles of food: id => %{id, cell, col, size, units, appeared, crossed}.
            # Pile `k` is on land `k`.
            piles: %{},
            # The river that the colony builds a bridge across now. After the last
            # crossing, it is the number of rivers plus 1.
            stage: 1,
            # The open cells of the river `stage`.
            open: MapSet.new(),
            # The time of the first lock of each bridge: river => time.
            first_lock: %{},
            food_nest: 0,
            # Units of food that count for the next new worker.
            food_credit: 0,
            # The tick of the last worker that the nest made because the colony had few workers.
            low_tick: 0,
            # Players and helpers: id => player.
            players: %{},
            next_player: 1,
            # The number of steps on foot from each cell to the nest.
            walk: %{},
            # For each pile: the number of steps on foot from each cell to the pile.
            to_pile: %{},
            # The number of steps on foot from each cell to the crossing place.
            front: %{},
            # The food that each player carried to the nest: {name, helper} => units.
            # `food_by` has all the food. `period` has the food from the last crossing.
            food_by: %{},
            period: %{},
            # The records of the bridges, the newest first.
            records: [],
            # The records that changed and that the clients do not have.
            records_dirty: [],
            # The time when the world became complete, or nil.
            complete: nil,
            # No helper locks before this tick.
            helper_tick: 0,
            events: nil

  @empty_events %{
    moves: [],
    worker_set: [],
    worker_gone: [],
    locks: [],
    scent: %{},
    names: [],
    you: [],
    records: [],
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

  @doc """
  Makes a world from the game config.

  `saved` is the term from `to_save/1`, or nil for a new world.
  """
  def new(cfg, saved \\ nil) do
    rate = Keyword.fetch!(cfg, :tick_rate)
    seed = (saved && saved.seed) || Keyword.get(cfg, :seed) || :rand.uniform(0x7FFFFFFF)
    grid = Grid.new(cfg, seed)

    p = %{
      rate: rate,
      step: Keyword.fetch!(cfg, :speed) / rate,
      leash: Keyword.fetch!(cfg, :leash),
      food_touch: Keyword.fetch!(cfg, :food_touch),
      nest_touch: Keyword.fetch!(cfg, :nest_touch),
      player_food: Keyword.fetch!(cfg, :player_food),
      pile_units: Keyword.fetch!(cfg, :pile_units),
      pile_rows: Keyword.fetch!(cfg, :pile_rows_from_river),
      pile_first_columns: Keyword.fetch!(cfg, :pile_first_columns),
      pile_edge_columns: Keyword.fetch!(cfg, :pile_edge_columns),
      pile_loss: Keyword.fetch!(cfg, :pile_loss_seconds),
      pile_least: Keyword.fetch!(cfg, :pile_least),
      start_columns: Keyword.fetch!(cfg, :start_columns),
      wait_part: Keyword.fetch!(cfg, :wait_part),
      takeover_ticks: round(Keyword.fetch!(cfg, :takeover_seconds) * rate),
      workers_max: Keyword.fetch!(cfg, :workers_max),
      food_per_worker: Keyword.fetch!(cfg, :food_per_worker),
      workers_low: Keyword.fetch!(cfg, :workers_low),
      worker_ticks: Keyword.fetch!(cfg, :worker_seconds) * rate,
      helpers: Keyword.fetch!(cfg, :helpers),
      helper_lock_ticks: Keyword.fetch!(cfg, :helper_lock_seconds) * rate,
      scent_max: Keyword.fetch!(cfg, :scent_max),
      scent_carry: Keyword.fetch!(cfg, :scent_carry),
      decay_ticks: Keyword.fetch!(cfg, :scent_decay_seconds) * rate
    }

    world = %__MODULE__{
      cfg: cfg,
      p: p,
      grid: grid,
      rule: Support.rule(cfg),
      seed: seed,
      rng: :rand.seed_s(:exsss, seed),
      events: @empty_events
    }

    world
    |> restore(saved)
    |> place_workers((saved && Map.get(saved, :workers)) || Keyword.fetch!(cfg, :workers))
    |> refresh_structure()
    |> refresh_ways()
    |> set_helpers(p.helpers)
  end

  # ---------------------------------------------------------------------------
  # Save and load

  @doc "The version of the save file. A file with a different version is not loaded."
  def save_version, do: 3

  @doc "The part of the world that goes into the save file."
  def to_save(%__MODULE__{} = world) do
    %{
      version: save_version(),
      seed: world.seed,
      start: world.start,
      locked:
        world.locked
        |> Enum.map(fn {cell, body} ->
          {cell, body.name, body.helper, body.time, body.n, body.crossings}
        end)
        |> Enum.sort(),
      lock_count: world.lock_count,
      scent: world.scent,
      piles: world.piles,
      stage: world.stage,
      first_lock: world.first_lock,
      food_nest: world.food_nest,
      food_credit: world.food_credit,
      workers: map_size(world.workers),
      food_by: world.food_by,
      period: world.period,
      records: world.records,
      complete: world.complete
    }
  end

  defp restore(world, %{version: 3} = saved) do
    grid = world.grid

    # A saved cell is used only if it is a river cell of this grid. The config can change
    # between two runs.
    locked =
      for {cell, name, helper, time, n, crossings} <- saved.locked,
          cell < grid.count and Grid.kind(grid, cell) == :gap,
          into: %{} do
        {cell, %{name: name, helper: helper, time: time, n: n, crossings: crossings}}
      end

    %{
      world
      | start: saved.start,
        locked: locked,
        lock_count: saved.lock_count,
        scent: Map.filter(saved.scent, fn {cell, _} -> cell < grid.count end),
        piles: saved.piles,
        stage: saved.stage,
        first_lock: saved.first_lock,
        food_nest: saved.food_nest,
        food_credit: saved.food_credit,
        food_by: saved.food_by,
        period: saved.period,
        records: saved.records,
        complete: saved.complete
    }
  end

  # No file, or a file of an older version of the game: a new world.
  defp restore(world, _saved), do: add_pile(world, 1)

  # The workers start near the nest.
  defp place_workers(world, count) do
    grid = world.grid

    spots =
      for cell <- 0..(grid.count - 1),
          Grid.kind(grid, cell) == :land,
          Grid.land(grid, cell) == 0,
          Grid.nest_distance(grid, cell) <= 3,
          do: cell

    spots = List.to_tuple(spots)

    Enum.reduce(0..(count - 1)//1, %{world | next_worker: count}, fn id, world ->
      {n, rng} = :rand.uniform_s(tuple_size(spots), world.rng)
      worker = %{cell: elem(spots, n - 1), carry: nil, mode: :idle}
      %{world | rng: rng, workers: Map.put(world.workers, id, worker)}
    end)
  end

  # ---------------------------------------------------------------------------
  # Players

  @doc """
  Adds a player. The player gets a body at the nest. This body does not use a spare body.
  Returns `{world, id}`.
  """
  def join(%__MODULE__{} = world, name), do: add_body(world, name, nil)

  defp add_body(world, name, helper) do
    id = free_player_id(world, world.next_player)
    {x, z} = Grid.center(world.grid, world.grid.nest)

    player = %{
      name: name,
      x: x,
      z: z,
      heading: 0.0,
      cell: world.grid.nest,
      budget: @budget_cap,
      # The food that the body carries: nil or %{pile, units}.
      carry: nil,
      # The body can lock from this tick.
      ready_tick: 0,
      # The worker whose body the player took at the last lock.
      took: nil,
      # nil for a person. For a helper: the state of its rules.
      helper: helper
    }

    world = %{
      world
      | players: Map.put(world.players, id, player),
        next_player: rem(id, 0xFFFE) + 1
    }

    {event(world, :names, {id, name, helper != nil}), id}
  end

  defp free_player_id(world, id) do
    if is_map_key(world.players, id), do: free_player_id(world, rem(id, 0xFFFE) + 1), else: id
  end

  @doc """
  A player gets a new name. The bodies that the player locked before keep the old name.
  """
  def rename(%__MODULE__{} = world, id, name) do
    case world.players do
      %{^id => %{helper: nil} = player} ->
        world
        |> put_player(id, %{player | name: name})
        |> event(:names, {id, name, false})

      _ ->
        world
    end
  end

  @doc "Removes a player. The locked bodies of the player stay."
  def leave(%__MODULE__{} = world, id) do
    %{world | players: Map.delete(world.players, id)}
  end

  @doc """
  A player tells where the body is now.

  The world accepts the position only if the body can be there: the cell is a land cell or
  a locked body, the distance is not more than the speed permits, and the straight way to
  the position does not go across a cell where a body cannot be. If not, the body stays
  where it was and the player gets the correct position.
  """
  def move(%__MODULE__{} = world, id, x, z, heading) do
    case world.players do
      %{^id => %{helper: nil} = player} ->
        distance = :math.sqrt((x - player.x) ** 2 + (z - player.z) ** 2)
        cell = stand_cell(world, x, z)
        player = %{player | heading: heading}

        if cell != nil and distance <= player.budget + 0.05 and
             clear_way?(world, player.x, player.z, x, z, distance) do
          world = if cell != player.cell, do: cross(world, cell), else: world
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

  # The cell where a body at a point stands, or nil if a body cannot be there.
  #
  # A position in a message has a step of 0.002. A body that is exactly on the edge of its
  # cell can thus be a very small distance outside of it. Such a body stands on its cell.
  @edge 0.004
  defp stand_cell(world, x, z) do
    Enum.find_value([{0.0, 0.0}, {@edge, 0.0}, {-@edge, 0.0}, {0.0, @edge}, {0.0, -@edge}], fn {dx,
                                                                                                dz} ->
      cell = Grid.cell_at(world.grid, x + dx, z + dz)
      if cell != nil and walkable?(world, cell), do: cell
    end)
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

  @doc """
  A player or a helper locks the body into a cell.

  A lock is possible only into an open cell that touches the cell of the body, and only
  if the colony has a spare body. The player then takes the body of the nearest worker.

  Returns `{:ok, world}` or `{{:error, reason}, world}`.
  """
  def lock(%__MODULE__{} = world, id, cell) do
    with %{} = player <- Map.get(world.players, id),
         true <- world.tick >= player.ready_tick,
         true <- is_integer(cell) and cell >= 0 and cell < world.grid.count,
         true <- cell in Grid.neighbors(world.grid, player.cell),
         true <- MapSet.member?(world.open, cell),
         true <- map_size(world.workers) > 0 do
      river = world.stage

      body = %{
        name: player.name,
        helper: player.helper != nil,
        time: world.now,
        n: world.lock_count + 1,
        crossings: 0
      }

      world =
        world
        |> put_lock(cell, body, id)
        |> take_body(id, player, cell)

      world =
        if Grid.touches_land?(world.grid, cell, river), do: crossing(world, river), else: world

      {:ok, world |> refresh_open() |> refresh_front()}
    else
      _ -> {{:error, :not_possible}, world}
    end
  end

  defp put_lock(world, cell, body, id) do
    locked = Map.put(world.locked, cell, body)
    river = Grid.river(world.grid, cell)

    world = %{
      world
      | locked: locked,
        lock_count: body.n,
        supports: Support.calculate(world.grid, world.rule, locked),
        first_lock: Map.put_new(world.first_lock, river, world.now)
    }

    # A body can walk on the new cell. The ways to the nest and to the piles change.
    %{
      world
      | walk: add_to_way(world, world.walk, cell),
        to_pile: Map.new(world.to_pile, fn {pile, way} -> {pile, add_to_way(world, way, cell)} end)
    }
    |> event(:locks, {cell, body, id})
    |> flag(:structure)
  end

  # The player gets the body of the worker that is nearest to the locked body by steps on
  # foot. A worker with no food is used first. The food that the old body carried is lost.
  defp take_body(world, id, player, cell) do
    {worker_id, at} =
      nearest_worker(world, cell, &(&1.carry == nil)) ||
        nearest_worker(world, cell, fn _ -> true end) ||
        any_worker(world)

    worker = Map.fetch!(world.workers, worker_id)
    {x, z} = Grid.center(world.grid, at)

    player = %{
      player
      | x: x,
        z: z,
        cell: at,
        budget: @budget_cap,
        ready_tick: world.tick + world.p.takeover_ticks,
        took: worker_id,
        carry: worker.carry && %{pile: worker.carry, units: 1}
    }

    %{
      world
      | players: Map.put(world.players, id, player),
        workers: Map.delete(world.workers, worker_id),
        freed_ids: [worker_id | world.freed_ids]
    }
    |> event(:worker_gone, worker_id)
  end

  defp nearest_worker(world, cell, use?) do
    # With more than one worker in a cell, the worker with the lowest number is used.
    by_cell =
      Enum.reduce(world.workers, %{}, fn {id, worker}, acc ->
        if use?.(worker), do: Map.update(acc, worker.cell, id, &min(&1, id)), else: acc
      end)

    if by_cell == %{}, do: nil, else: search_worker(world, by_cell, [cell], MapSet.new([cell]))
  end

  defp search_worker(_world, _by_cell, [], _seen), do: nil

  defp search_worker(world, by_cell, front, seen) do
    case front |> Enum.filter(&is_map_key(by_cell, &1)) |> Enum.min(fn -> nil end) do
      nil ->
        {next, seen} =
          Enum.reduce(front, {[], seen}, fn cell, acc ->
            Enum.reduce(Grid.neighbors(world.grid, cell), acc, fn to, {next, seen} = acc ->
              if MapSet.member?(seen, to) or not walkable?(world, to) do
                acc
              else
                {[to | next], MapSet.put(seen, to)}
              end
            end)
          end)

        search_worker(world, by_cell, next, seen)

      at ->
        {Map.fetch!(by_cell, at), at}
    end
  end

  # A worker that no way on foot gets to. This does not occur in a game that runs.
  defp any_worker(world) do
    {id, worker} = Enum.min(world.workers)
    {id, worker.cell}
  end

  @doc "The data of a locked body for a player who taps it, or nil."
  def body(%__MODULE__{} = world, cell) do
    case Map.get(world.locked, cell) do
      nil -> nil
      body -> Map.put(body, :support, Map.get(world.supports, cell, 0))
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers

  @doc "Makes the number of helpers `wanted`."
  def set_helpers(%__MODULE__{} = world, wanted) do
    now = for {id, %{helper: %{n: n}}} <- world.players, do: {n, id}
    count = length(now)

    cond do
      count < wanted ->
        used = MapSet.new(now, &elem(&1, 0))
        n = Enum.find(1..(count + 1), &(not MapSet.member?(used, &1)))
        {world, _id} = add_body(world, "Helper #{n}", Helpers.new(n))
        set_helpers(world, wanted)

      count > wanted ->
        {_n, id} = Enum.max(now)
        set_helpers(leave(world, id), wanted)

      true ->
        world
    end
  end

  # ---------------------------------------------------------------------------
  # Queries

  @doc "True if a free body can be on the cell."
  def walkable?(world, cell) do
    Grid.kind(world.grid, cell) != :gap or is_map_key(world.locked, cell)
  end

  @doc "True if the cell is open: a lock there is possible and helps."
  def open?(world, cell), do: MapSet.member?(world.open, cell)

  @doc "The number of spare bodies. Each worker is a spare body."
  def spare(world), do: map_size(world.workers)

  @doc "The number of rivers."
  def rivers(world), do: Grid.river_count(world.grid)

  @doc "The scent of a cell."
  def scent(world, cell), do: Map.get(world.scent, cell, 0)

  @doc "The locked bodies of river `k`: the bridge to land `k`."
  def bridge(world, k) do
    for {cell, _} <- world.locked, Grid.river(world.grid, cell) == k, do: cell
  end

  @doc "True if the bridge of river `k` touches land `k`."
  def complete?(world, k), do: k < world.stage

  @doc "The pile that no body can walk to, or nil."
  def far_pile(world) do
    case Map.get(world.piles, world.stage) do
      %{crossed: nil} = pile -> pile
      _ -> nil
    end
  end

  @doc """
  The story: all the locks in the order of their times, and the players with their bodies
  and their food.
  """
  def story(%__MODULE__{} = world) do
    locks =
      world.locked
      |> Enum.sort_by(fn {_cell, body} -> body.n end)
      |> Enum.map(fn {cell, body} ->
        %{
          n: body.n,
          cell: cell,
          river: Grid.river(world.grid, cell),
          name: body.name,
          helper: body.helper,
          time: body.time
        }
      end)

    bodies = Enum.frequencies_by(locks, &{&1.name, &1.helper})

    names =
      for key <- Enum.uniq(Map.keys(bodies) ++ Map.keys(world.food_by)) do
        {name, helper} = key

        %{
          name: name,
          helper: helper,
          bodies: Map.get(bodies, key, 0),
          food: Map.get(world.food_by, key, 0)
        }
      end
      |> Enum.sort_by(&{-&1.bodies, -&1.food, &1.name})

    %{
      start: world.start,
      time: world.now,
      complete: world.complete,
      crossings: world.stage - 1,
      rivers: rivers(world),
      food: world.food_nest,
      names: names,
      locks: locks
    }
  end

  # ---------------------------------------------------------------------------
  # Changes that the worker rules and the helper rules also use

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
  # A free body goes on a cell. If a locked body is there, its count goes up.
  def cross(world, cell) do
    case world.locked do
      %{^cell => body} ->
        %{world | locked: Map.put(world.locked, cell, %{body | crossings: body.crossings + 1})}

      _ ->
        world
    end
  end

  @doc false
  # A body takes units from a pile. Returns `{world, units}`.
  def take_food(world, pile_id, wanted) do
    pile = Map.fetch!(world.piles, pile_id)
    units = min(wanted, pile.units)
    world = %{world | piles: Map.put(world.piles, pile_id, %{pile | units: pile.units - units})}
    {flag(world, :food), units}
  end

  @doc false
  # Units of food from the pile `pile_id` get to the nest. `by` is `{name, helper}` for the
  # food that a player carried, or nil for a worker.
  def add_nest_food(world, pile_id, units, by \\ nil) do
    world = flag(%{world | food_nest: world.food_nest + units}, :food)
    world = make_workers(%{world | food_credit: world.food_credit + units})
    world = %{world | piles: Map.update!(world.piles, pile_id, &%{&1 | fed: true})}

    world =
      if by == nil do
        world
      else
        %{
          world
          | food_by: Map.update(world.food_by, by, units, &(&1 + units)),
            period: Map.update(world.period, by, units, &(&1 + units))
        }
        |> count_last_record(by, units)
      end

    # The first food of the last pile makes the world complete.
    if world.complete == nil and pile_id == rivers(world) do
      flag(%{world | complete: world.now}, :food)
    else
      world
    end
  end

  @doc false
  def put_player(world, id, player), do: %{world | players: Map.put(world.players, id, player)}

  # ---------------------------------------------------------------------------
  # Workers of the nest

  # The nest makes one worker for each `food_per_worker` units of food.
  defp make_workers(world) do
    if world.food_credit >= world.p.food_per_worker and
         map_size(world.workers) < world.p.workers_max do
      make_workers(make_worker(%{world | food_credit: world.food_credit - world.p.food_per_worker}))
    else
      %{world | food_credit: min(world.food_credit, world.p.food_per_worker)}
    end
  end

  # The nest makes a new worker, if the colony has room.
  defp make_worker(world) do
    if map_size(world.workers) >= world.p.workers_max do
      world
    else
      {id, world} =
        case world.free_ids do
          [id | rest] -> {id, %{world | free_ids: rest}}
          [] -> {world.next_worker, %{world | next_worker: world.next_worker + 1}}
        end

      worker = %{cell: world.grid.nest, carry: nil, mode: :idle}

      %{world | workers: Map.put(world.workers, id, worker)}
      # Flag 2: the worker starts at a new position.
      |> event(:worker_set, {id, world.grid.nest, 2})
    end
  end

  # With few spare bodies, the nest makes one worker each some seconds.
  defp low_workers(world) do
    cond do
      map_size(world.workers) >= world.p.workers_low ->
        %{world | low_tick: world.tick}

      world.tick - world.low_tick >= world.p.worker_ticks ->
        make_worker(%{world | low_tick: world.tick})

      true ->
        world
    end
  end

  # ---------------------------------------------------------------------------
  # The piles

  # Pile `k` appears on land `k`, some rows after the river.
  defp add_pile(world, k) do
    grid = world.grid
    {col, world} = pile_column(world, k)
    row = Grid.river_start(grid, k) + Grid.river_width(grid, k, col) + world.p.pile_rows - 1
    cell = Grid.cell(grid, row, col)
    size = Enum.at(world.p.pile_units, k - 1) || List.last(world.p.pile_units)

    pile = %{
      id: k,
      cell: cell,
      col: col,
      size: size,
      units: size,
      appeared: world.now,
      # The time of the crossing to the land of the pile. Before it, no body can walk to
      # the pile, and the pile loses units.
      crossed: nil,
      # True after the first food of the pile got to the nest.
      fed: false
    }

    way = flood(grid, [cell], %{cell => 0}, 1, :infinity, &walkable?(world, &1))

    %{world | piles: Map.put(world.piles, k, pile), to_pile: Map.put(world.to_pile, k, way)}
    |> flag(:food)
  end

  # Pile 1 is near the column of the nest. Each later pile is in a random column that is
  # not near an edge of the world.
  defp pile_column(world, k) do
    grid = world.grid
    last = grid.width - 1
    nest_col = Grid.col(grid, grid.nest)

    {low, high} =
      if k == 1 do
        {max(0, nest_col - world.p.pile_first_columns),
         min(last, nest_col + world.p.pile_first_columns)}
      else
        margin = min(world.p.pile_edge_columns, div(last, 2))
        {margin, last - margin}
      end

    {n, rng} = :rand.uniform_s(high - low + 1, world.rng)
    {low + n - 1, %{world | rng: rng}}
  end

  # A pile that no body can walk to loses units, down to a limit.
  defp pile_loss(world) do
    with true <- rem(div(world.tick, world.p.rate), world.p.pile_loss) == 0,
         %{units: units} = pile when units > world.p.pile_least <- far_pile(world) do
      flag(%{world | piles: Map.put(world.piles, pile.id, %{pile | units: units - 1})}, :food)
    else
      _ -> world
    end
  end

  # ---------------------------------------------------------------------------
  # The crossing and the records

  # The bridge of river `k` touches land `k`.
  defp crossing(world, k) do
    pile = %{Map.fetch!(world.piles, k) | crossed: world.now}
    world = %{world | piles: Map.put(world.piles, k, pile), stage: k + 1}
    world = make_record(world, k, pile)
    world = send_to_pile(%{world | period: %{}}, k)
    if k < rivers(world), do: add_pile(world, k + 1), else: flag(world, :food)
  end

  # At a crossing, the workers that waited go across the bridge. The worker at the end of
  # the line goes to the new pile. The other workers go to the next crossing place: they
  # stay spare bodies near the player who made the crossing. After the last crossing, all
  # of them go to the pile. See also `Colony.Workers`: a new pile calls workers.
  defp send_to_pile(world, k) do
    way = Map.fetch!(world.to_pile, k)
    waiting = for {_id, %{mode: :wait}} = entry <- world.workers, do: entry
    count = if k == rivers(world), do: length(waiting), else: 1

    workers =
      waiting
      |> Enum.sort_by(fn {id, worker} -> {Map.get(way, worker.cell, 1_000_000), id} end, :desc)
      |> Enum.take(count)
      |> Enum.reduce(world.workers, fn {id, worker}, workers ->
        Map.put(workers, id, %{worker | mode: {:fetch, k}})
      end)

    %{world | workers: workers}
  end

  defp make_record(world, k, pile) do
    grid = world.grid
    cells = bridge(world, k)

    bodies =
      cells
      |> Enum.map(&Map.fetch!(world.locked, &1))
      |> Enum.frequencies_by(&{&1.name, &1.helper})

    record = %{
      id: k,
      time: world.now,
      # The seconds from the first lock of the bridge to the crossing.
      seconds: max(0, world.now - Map.get(world.first_lock, k, world.now)),
      names: record_names(bodies, world.period),
      bodies: length(cells),
      rows: cells |> Enum.map(&Grid.row(grid, &1)) |> Enum.uniq() |> length(),
      # The width of the river in the widest column of the bridge.
      width: cells |> Enum.map(&Grid.river_width(grid, k, Grid.col(grid, &1))) |> Enum.max(),
      # The units of the pile at the crossing, and its units at the start.
      left: pile.units,
      size: pile.size
    }

    %{world | records: [record | world.records]}
    # Each player sees this record immediately.
    |> event(:records, Map.put(record, :first, true))
  end

  defp record_names(bodies, food) do
    for key <- Enum.uniq(Map.keys(bodies) ++ Map.keys(food)) do
      {name, helper} = key
      %{name: name, helper: helper, bodies: Map.get(bodies, key, 0), food: Map.get(food, key, 0)}
    end
    |> Enum.sort_by(&{-&1.bodies, -&1.food, &1.name})
  end

  # After the last crossing, the food that a player carries counts in the last record.
  defp count_last_record(world, by, units) do
    with true <- world.stage > rivers(world), [record | rest] <- world.records do
      {name, helper} = by

      names =
        case Enum.split_with(record.names, &(&1.name == name and &1.helper == helper)) do
          {[entry], others} -> [%{entry | food: entry.food + units} | others]
          {[], others} -> [%{name: name, helper: helper, bodies: 0, food: units} | others]
        end
        |> Enum.sort_by(&{-&1.bodies, -&1.food, &1.name})

      %{
        world
        | records: [%{record | names: names} | rest],
          records_dirty: Enum.uniq([record.id | world.records_dirty])
      }
    else
      _ -> world
    end
  end

  # The clients get the records that changed, one time each second at most.
  defp send_records(%{records_dirty: []} = world), do: world

  defp send_records(world) do
    world.records
    |> Enum.filter(&(&1.id in world.records_dirty))
    |> Enum.reduce(%{world | records_dirty: []}, &event(&2, :records, &1))
  end

  # ---------------------------------------------------------------------------
  # The step

  @doc """
  Moves the world one tick.

  `now` is the time in seconds. It goes into the locked bodies and the records. With nil,
  the time is the number of seconds of world time.

  Returns `{world, events}`.
  """
  def tick(%__MODULE__{} = world, now \\ nil) do
    tick = world.tick + 1
    now = now || div(tick, world.p.rate)
    world = %{world | tick: tick, now: now, start: world.start || now}

    world
    |> each_second()
    |> step_players()
    |> Helpers.step()
    |> Workers.step()
    |> take_events()
  end

  @doc "Returns `{world, events}` and removes the events from the world."
  def take_events(%__MODULE__{} = world) do
    free_ids = world.free_ids ++ world.freed_ids
    {%{world | events: @empty_events, free_ids: free_ids, freed_ids: []}, world.events}
  end

  defp each_second(world) do
    if rem(world.tick, world.p.rate) == 0 do
      world
      |> decay_scent()
      |> pile_loss()
      |> low_workers()
      |> send_records()
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

  defp step_players(world) do
    Enum.reduce(world.players, world, fn {id, player}, world ->
      # The 1.15 lets a client clock be a small quantity faster than the server clock.
      player = %{player | budget: min(@budget_cap, player.budget + world.p.step * 1.15)}

      world
      |> put_player(id, player)
      |> carry_food(id, player)
    end)
  end

  # A player who touches a pile takes food. A player with food who touches the nest puts
  # the food into the nest. A helper takes food only when it goes for food.
  defp carry_food(world, id, %{carry: nil} = player) do
    if player.helper == nil or player.helper.goal == :food do
      pile =
        Enum.find_value(world.piles, fn {_id, pile} ->
          if pile.units > 0 and pile.crossed != nil and
               near?(world, player, pile.cell, world.p.food_touch),
             do: pile
        end)

      if pile do
        {world, units} = take_food(world, pile.id, world.p.player_food)
        put_player(world, id, %{player | carry: %{pile: pile.id, units: units}})
      else
        world
      end
    else
      world
    end
  end

  defp carry_food(world, id, %{carry: carry} = player) do
    if near?(world, player, world.grid.nest, world.p.nest_touch) do
      world
      |> put_player(id, %{player | carry: nil})
      |> add_nest_food(carry.pile, carry.units, {player.name, player.helper != nil})
    else
      world
    end
  end

  defp near?(world, player, cell, distance) do
    {x, z} = Grid.center(world.grid, cell)
    (player.x - x) ** 2 + (player.z - z) ** 2 <= distance ** 2
  end

  # ---------------------------------------------------------------------------
  # Values that are calculated from the state

  # After a load: the bodies with no support fall. In a game that runs, no step removes
  # a body, thus no body loses its support.
  defp refresh_structure(world) do
    {supports, fallen} = Support.settle(world.grid, world.rule, world.locked)
    %{world | locked: Map.drop(world.locked, fallen), supports: supports}
  end

  # All the values that tell a body where to go.
  defp refresh_ways(world) do
    grid = world.grid
    open? = &walkable?(world, &1)
    walk = flood(grid, [grid.nest], %{grid.nest => 0}, 1, :infinity, open?)

    to_pile =
      Map.new(world.piles, fn {id, pile} ->
        {id, flood(grid, [pile.cell], %{pile.cell => 0}, 1, :infinity, open?)}
      end)

    %{world | walk: walk, to_pile: to_pile}
    |> refresh_open()
    |> refresh_front()
  end

  # The open cells of the river that the colony builds a bridge across now.
  defp refresh_open(world) do
    case far_pile(world) do
      nil ->
        flag(%{world | open: MapSet.new()}, :structure)

      pile ->
        grid = world.grid
        row = Grid.river_start(grid, pile.id)

        start =
          for col <- 0..(grid.width - 1),
              abs(col - pile.col) <= world.p.start_columns,
              do: Grid.cell(grid, row, col)

        open = Support.open(grid, world.rule, world.locked, pile.id, start)
        flag(%{world | open: MapSet.new(open)}, :structure)
    end
  end

  # The number of steps on foot to the crossing place: the cells where a body can stand
  # and lock into an open cell. With no bridge, these are the cells at the edge of the
  # land, near the column of the pile. With a bridge, they are bodies of the bridge.
  defp refresh_front(world) do
    sources =
      for cell <- world.open,
          to <- Grid.neighbors(world.grid, cell),
          walkable?(world, to),
          uniq: true,
          do: to

    if sources == [] do
      %{world | front: %{}}
    else
      start = Map.new(sources, &{&1, 0})
      %{world | front: flood(world.grid, sources, start, 1, :infinity, &walkable?(world, &1))}
    end
  end

  # A body can walk on a new cell. This changes a map of steps: the new cell gets its
  # number, and each cell that now has a shorter way gets a smaller number.
  defp add_to_way(world, way, cell) do
    near =
      for to <- Grid.neighbors(world.grid, cell), steps = Map.get(way, to), steps != nil, do: steps

    case near do
      [] -> way
      list -> shorten(world, [cell], Map.put(way, cell, Enum.min(list) + 1))
    end
  end

  defp shorten(_world, [], way), do: way

  defp shorten(world, front, way) do
    {next, way} =
      Enum.reduce(front, {[], way}, fn cell, acc ->
        steps = Map.fetch!(elem(acc, 1), cell) + 1

        Enum.reduce(Grid.neighbors(world.grid, cell), acc, fn to, {next, way} = acc ->
          if walkable?(world, to) and Map.get(way, to, :infinity) > steps do
            {[to | next], Map.put(way, to, steps)}
          else
            acc
          end
        end)
      end)

    shorten(world, next, way)
  end

  @doc false
  # The number of steps from the cells of `front` to each cell that `open?` permits.
  def flood(_grid, [], distances, _distance, _limit, _open?), do: distances

  def flood(_grid, _front, distances, distance, limit, _open?) when distance > limit,
    do: distances

  def flood(grid, front, distances, distance, limit, open?) do
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
