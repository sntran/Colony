defmodule Colony.World do
  @moduledoc """
  The state of the world and the rules that change it.

  This module has no processes and no clock. `tick/2` moves the world one step. The server
  process calls it 10 times each second. The tests call it as fast as possible.

  Each change that a client must know is added to `events`. `tick/2` returns the events of
  the step and removes them from the world.

  The rules of plan 0002:

  - Only a player or a helper locks. A worker never locks.
  - After a lock, the player takes the body of the nearest free worker.
  - There is one pile of food at a time. A pile with 0 units makes the next pile.
  - The first food of a pile makes a record of the bridge that it crossed.
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
            # Free workers: id => %{cell, carry, mode, crossed}.
            workers: %{},
            # Worker numbers that are free for a new worker.
            free_ids: [],
            next_worker: 0,
            # Locked bodies: cell => %{name, helper, time, crossings}.
            locked: %{},
            # Support of the locked bodies: cell => support, as an integer.
            supports: %{},
            # Scent: cell => 1..100.
            scent: %{},
            # The pile of food: %{id, cell, col, width, units, appeared, first_lock, taken}.
            pile: nil,
            # The piles before this one: id => %{start, width}.
            history: %{},
            food_nest: 0,
            # Units of food that count for the next new worker.
            food_credit: 0,
            # The tick of the last worker that the nest made because the colony had few workers.
            low_tick: 0,
            # Players and helpers: id => player.
            players: %{},
            next_player: 1,
            demo: false,
            # The number of steps on foot from each cell to the nest.
            walk: %{},
            walk_dirty: true,
            # The number of steps on foot from each cell near the pile to the pile.
            to_pile: %{},
            # The number of steps from each locked body to the far bank, along locked bodies.
            to_far: %{},
            # The cells that are near scent or near the nest: cell => distance.
            leash: %{},
            # The records of the bridges, the newest first.
            records: [],
            # The records that changed and that the clients do not have.
            records_dirty: [],
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
  # The first and the last columns have no pile.
  @pile_margin 2

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
      food_radius: Keyword.fetch!(cfg, :food_radius),
      food_touch: Keyword.fetch!(cfg, :food_touch),
      pile_units: Keyword.fetch!(cfg, :pile_units),
      pile_rows: Keyword.fetch!(cfg, :pile_rows_from_river),
      pile_widths: Keyword.fetch!(cfg, :pile_widths),
      pile_bridge_columns: Keyword.fetch!(cfg, :pile_bridge_columns),
      pile_loss: Keyword.fetch!(cfg, :pile_loss_seconds),
      takeover_ticks: Keyword.fetch!(cfg, :takeover_seconds) * rate,
      respawn_ticks: Keyword.fetch!(cfg, :respawn_seconds) * rate,
      workers_max: Keyword.fetch!(cfg, :workers_max),
      food_per_worker: Keyword.fetch!(cfg, :food_per_worker),
      workers_low: Keyword.fetch!(cfg, :workers_low),
      worker_ticks: Keyword.fetch!(cfg, :worker_seconds) * rate,
      helpers: Keyword.fetch!(cfg, :helpers),
      helper_lock_ticks: Keyword.fetch!(cfg, :helper_lock_seconds) * rate,
      demo_helpers: Keyword.fetch!(cfg, :demo_helpers),
      scent_max: Keyword.fetch!(cfg, :scent_max),
      scent_player: Keyword.fetch!(cfg, :scent_player),
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
    |> refresh_walk()
    |> refresh_leash()
    |> set_helpers(p.helpers)
  end

  # ---------------------------------------------------------------------------
  # Save and load

  @doc "The part of the world that goes into the save file."
  def to_save(%__MODULE__{} = world) do
    %{
      version: 2,
      seed: world.seed,
      locked:
        world.locked
        |> Enum.map(fn {cell, body} ->
          {cell, body.name, body.helper, body.time, body.crossings}
        end)
        |> Enum.sort(),
      scent: world.scent,
      pile: world.pile,
      history: world.history,
      food_nest: world.food_nest,
      food_credit: world.food_credit,
      workers: map_size(world.workers),
      records: world.records
    }
  end

  defp restore(world, %{version: 2} = saved) do
    grid = world.grid

    # A saved cell is used only if it is a river cell of this grid. The config can change
    # between two runs.
    locked =
      for {cell, name, helper, time, crossings} <- saved.locked,
          cell < grid.count and Grid.kind(grid, cell) == :gap,
          into: %{} do
        {cell, %{name: name, helper: helper, time: time, crossings: crossings}}
      end

    %{
      world
      | locked: locked,
        scent: Map.filter(saved.scent, fn {cell, _} -> cell < grid.count end),
        pile: saved.pile,
        history: saved.history,
        food_nest: saved.food_nest,
        food_credit: saved.food_credit,
        records: saved.records
    }
  end

  # No file, or a file of an older version of the game: a new world.
  defp restore(world, _saved), do: %{world | pile: first_pile(world)}

  # The workers start near the nest.
  defp place_workers(world, count) do
    grid = world.grid

    spots =
      for cell <- 0..(grid.count - 1),
          Grid.kind(grid, cell) == :near,
          Grid.nest_distance(grid, cell) <= 3,
          do: cell

    spots = List.to_tuple(spots)

    Enum.reduce(0..(count - 1)//1, %{world | next_worker: count}, fn id, world ->
      {n, rng} = :rand.uniform_s(tuple_size(spots), world.rng)
      worker = %{cell: elem(spots, n - 1), carry: nil, mode: :out, crossed: nil}
      %{world | rng: rng, workers: Map.put(world.workers, id, worker)}
    end)
  end

  # ---------------------------------------------------------------------------
  # Players

  @doc "Adds a player. The player gets a body at the nest. Returns `{world, id}`."
  def join(%__MODULE__{} = world, name), do: add_body(world, name, nil)

  defp add_body(world, name, helper) do
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
      # The pile that this player got the message of.
      touched: nil,
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
      %{^id => %{state: :alive, helper: nil} = player} ->
        distance = :math.sqrt((x - player.x) ** 2 + (z - player.z) ** 2)
        cell = Grid.cell_at(world.grid, x, z)
        player = %{player | heading: heading, scent: scent?}

        if cell != nil and walkable?(world, cell) and distance <= player.budget + 0.05 and
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

  Then the player takes the body of the nearest free worker. With no free worker, the
  player gets a new body at the nest after some seconds.

  Returns `{:ok, world}` or `{{:error, reason}, world}`.
  """
  def lock(%__MODULE__{} = world, id, cell) do
    with %{state: :alive} = player <- Map.get(world.players, id),
         true <- world.tick >= player.ready_tick,
         true <- is_integer(cell) and cell >= 0 and cell < world.grid.count,
         true <- cell in Grid.neighbors(world.grid, player.cell),
         true <- can_lock?(world, cell) do
      body = %{
        name: player.name,
        helper: player.helper != nil,
        time: world.now,
        crossings: 0
      }

      world =
        world
        |> put_lock(cell, body, id)
        |> take_body(id, player, cell)

      {:ok, world}
    else
      _ -> {{:error, :not_possible}, world}
    end
  end

  defp put_lock(world, cell, body, id) do
    locked = Map.put(world.locked, cell, body)
    pile = world.pile
    pile = if pile.first_lock == nil, do: %{pile | first_lock: world.now}, else: pile

    %{
      world
      | locked: locked,
        supports: Support.calculate(world.grid, world.rule, locked),
        pile: pile,
        walk_dirty: true
    }
    |> event(:locks, {cell, body, id})
    |> flag(:structure)
  end

  # The player gets the body of the free worker that is nearest to the locked body by
  # steps on foot. A worker that carries food is not used.
  defp take_body(world, id, player, cell) do
    case nearest_worker(world, cell) do
      nil ->
        player = %{
          player
          | state: {:dead, world.tick + world.p.respawn_ticks},
            scent: false,
            took: nil
        }

        %{world | players: Map.put(world.players, id, player)}

      {worker_id, at} ->
        {x, z} = Grid.center(world.grid, at)

        player = %{
          player
          | x: x,
            z: z,
            cell: at,
            budget: @budget_cap,
            ready_tick: world.tick + world.p.takeover_ticks,
            took: worker_id
        }

        %{
          world
          | players: Map.put(world.players, id, player),
            workers: Map.delete(world.workers, worker_id),
            free_ids: [worker_id | world.free_ids]
        }
        |> event(:worker_gone, worker_id)
    end
  end

  defp nearest_worker(world, cell) do
    # With more than one worker in a cell, the worker with the lowest number is used.
    by_cell =
      Enum.reduce(world.workers, %{}, fn
        {id, %{carry: nil, cell: at}}, acc -> Map.update(acc, at, id, &min(&1, id))
        _, acc -> acc
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

  @doc "The data of a locked body for a player who taps it, or nil."
  def body(%__MODULE__{} = world, cell) do
    case Map.get(world.locked, cell) do
      nil -> nil
      body -> Map.put(body, :support, Map.get(world.supports, cell, 0))
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers and the demo mode

  @doc "Starts or stops the demo mode. The demo mode has helpers and no player."
  def set_demo(%__MODULE__{} = world, demo?) do
    wanted = if demo?, do: max(world.p.helpers, world.p.demo_helpers), else: world.p.helpers
    set_helpers(%{world | demo: demo?}, wanted)
  end

  @doc "Makes the number of helpers `wanted`."
  def set_helpers(%__MODULE__{} = world, wanted) do
    now = for {id, %{helper: %{n: n}}} <- world.players, do: {n, id}
    count = length(now)

    cond do
      count < wanted ->
        used = MapSet.new(now, &elem(&1, 0))
        n = Enum.find(1..(count + 1), &(not MapSet.member?(used, &1)))
        # `shown`: the pile that the helper showed the way to.
        helper = %{n: n, next_lock: world.tick, plan: nil, path: [], shown: nil}
        {world, _id} = add_body(world, "Helper #{n}", helper)
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

  @doc "True if a body can lock into the cell now."
  def can_lock?(world, cell) do
    Support.can_lock?(world.grid, world.rule, world.locked, cell)
  end

  @doc "The scent of a cell."
  def scent(world, cell), do: Map.get(world.scent, cell, 0)

  @doc "The groups of locked bodies that touch each other, as a list of sets of cells."
  def bridges(world) do
    {groups, _seen} =
      Enum.reduce(world.locked, {[], MapSet.new()}, fn {cell, _}, {groups, seen} = acc ->
        if MapSet.member?(seen, cell) do
          acc
        else
          group = Support.group(world.grid, world.locked, cell)
          {[group | groups], MapSet.union(seen, group)}
        end
      end)

    groups
  end

  @doc "True if a group of locked bodies touches the two banks."
  def complete?(world, group) do
    kinds =
      for cell <- group, next <- Grid.neighbors(world.grid, cell), into: MapSet.new() do
        Grid.kind(world.grid, next)
      end

    MapSet.member?(kinds, :near) and MapSet.member?(kinds, :far)
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
  # A worker takes one unit from the pile. The first unit stops the loss of the pile.
  def take_food(world) do
    pile = %{world.pile | units: world.pile.units - 1, taken: true}
    world = flag(%{world | pile: pile}, :food)
    if pile.units == 0, do: next_pile(world), else: world
  end

  @doc false
  # A worker brings one unit of food from the pile `pile_id` to the nest.
  # `crossed` is a locked body that the worker went on.
  def add_nest_food(world, pile_id, crossed) do
    world = flag(%{world | food_nest: world.food_nest + 1}, :food)
    credit = world.food_credit + 1

    world =
      if credit >= world.p.food_per_worker and map_size(world.workers) < world.p.workers_max do
        make_worker(%{world | food_credit: credit - world.p.food_per_worker})
      else
        %{world | food_credit: min(credit, world.p.food_per_worker)}
      end

    record_food(world, pile_id, crossed)
  end

  @doc false
  def put_player(world, id, player), do: %{world | players: Map.put(world.players, id, player)}

  # ---------------------------------------------------------------------------
  # Workers of the nest

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

      worker = %{cell: world.grid.nest, carry: nil, mode: :out, crossed: nil}

      %{world | workers: Map.put(world.workers, id, worker)}
      # Flag 2: the worker starts at a new position.
      |> event(:worker_set, {id, world.grid.nest, 2})
    end
  end

  # With few free workers, the nest makes one worker each some seconds.
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
  # The pile

  # The first pile is across the narrowest place of the river.
  defp first_pile(world) do
    grid = world.grid
    {_row, nest_col} = Keyword.fetch!(world.cfg, :nest)

    col =
      Enum.min_by(pile_columns(grid), fn col ->
        {Grid.river_width(grid, col), abs(col - nest_col)}
      end)

    make_pile(world, 1, col)
  end

  # The columns where a pile can be. A grid with few columns has a smaller margin.
  defp pile_columns(grid) do
    margin = min(@pile_margin, div(grid.width - 1, 2))
    Enum.to_list(margin..(grid.width - 1 - margin))
  end

  defp make_pile(world, id, col) do
    grid = world.grid
    width = Grid.river_width(grid, col)

    %{
      id: id,
      cell: Grid.cell(grid, grid.near_rows + width + world.p.pile_rows - 1, col),
      col: col,
      width: width,
      units: world.p.pile_units,
      appeared: world.now,
      # The time of the first lock after the pile appeared.
      first_lock: nil,
      # True after a worker took food from the pile.
      taken: false
    }
  end

  # From the first lock to the first food, the pile loses units.
  defp pile_loss(%{pile: %{first_lock: lock, taken: false, units: units} = pile} = world)
       when lock != nil and units > 0 do
    if rem(div(world.tick, world.p.rate), world.p.pile_loss) == 0 do
      world = flag(%{world | pile: %{pile | units: units - 1}}, :food)
      if units == 1, do: next_pile(world), else: world
    else
      world
    end
  end

  defp pile_loss(world), do: world

  # The pile has 0 units. The next pile appears across a wider place.
  defp next_pile(world) do
    old = world.pile

    history =
      Map.put(world.history, old.id, %{start: old.first_lock || old.appeared, width: old.width})

    {col, world} = pile_column(world, old.id + 1)

    %{world | history: history, pile: make_pile(world, old.id + 1, col), walk_dirty: true}
    |> finish_records()
    |> flag(:food)
  end

  defp pile_column(world, id) do
    grid = world.grid

    columns =
      case Enum.reject(pile_columns(grid), &(&1 == world.pile.col)) do
        [] -> [world.pile.col]
        columns -> columns
      end

    # A new pile is some columns or more from each complete bridge, if that is possible.
    bridge_columns =
      for group <- bridges(world), complete?(world, group), cell <- group, uniq: true do
        Grid.col(grid, cell)
      end

    far =
      Enum.filter(columns, fn col ->
        Enum.all?(bridge_columns, &(abs(&1 - col) >= world.p.pile_bridge_columns))
      end)

    columns = if far == [], do: columns, else: far

    # The pile number 2 is at the first width of the list. After the list, the place is random.
    columns =
      case Enum.at(world.p.pile_widths, id - 2) do
        nil ->
          columns

        target ->
          best = columns |> Enum.map(&abs(Grid.river_width(grid, &1) - target)) |> Enum.min()
          Enum.filter(columns, &(abs(Grid.river_width(grid, &1) - target) == best))
      end

    {n, rng} = :rand.uniform_s(length(columns), world.rng)
    {Enum.at(columns, n - 1), %{world | rng: rng}}
  end

  # ---------------------------------------------------------------------------
  # Records

  # One unit of food from a pile is at the nest. The first unit of a pile makes the
  # record of the bridge that the worker crossed.
  defp record_food(world, pile_id, crossed) do
    case Enum.find(world.records, &(&1.id == pile_id)) do
      nil -> make_record(world, pile_id, crossed)
      record -> put_record(world, %{record | food: record.food + 1})
    end
    |> finish_records()
  end

  defp make_record(world, pile_id, crossed) do
    grid = world.grid

    {start, width} =
      case world.history do
        %{^pile_id => %{start: start, width: width}} -> {start, width}
        _ -> {world.pile.first_lock || world.pile.appeared, world.pile.width}
      end

    group =
      if crossed != nil and is_map_key(world.locked, crossed),
        do: Support.group(grid, world.locked, crossed),
        else: MapSet.new()

    names =
      group
      |> Enum.map(&Map.fetch!(world.locked, &1))
      |> Enum.group_by(&{&1.name, &1.helper})
      |> Enum.map(fn {{name, helper}, bodies} ->
        %{name: name, helper: helper, bodies: length(bodies)}
      end)
      |> Enum.sort_by(&{-&1.bodies, &1.name})

    rows = group |> Enum.map(&Grid.row(grid, &1)) |> Enum.uniq() |> length()

    record = %{
      id: pile_id,
      time: world.now,
      # The seconds from the first lock to the first food.
      seconds: max(0, world.now - start),
      names: names,
      bodies: MapSet.size(group),
      rows: rows,
      width: width,
      food: 1,
      # True when the pile has 0 units and all its food is at the nest.
      done: false
    }

    %{world | records: [record | world.records], records_dirty: [pile_id | world.records_dirty]}
    # The players with a body in the bridge see this record immediately.
    |> event(:records, Map.put(record, :first, true))
  end

  defp put_record(world, record) do
    records = Enum.map(world.records, &if(&1.id == record.id, do: record, else: &1))
    %{world | records: records, records_dirty: Enum.uniq([record.id | world.records_dirty])}
  end

  # A record is complete when its pile has 0 units and no worker carries food from it.
  defp finish_records(world) do
    carried =
      for {_id, %{carry: pile_id}} <- world.workers, pile_id != nil, into: MapSet.new(), do: pile_id

    Enum.reduce(world.records, world, fn record, world ->
      if not record.done and record.id < world.pile.id and not MapSet.member?(carried, record.id) do
        put_record(world, %{record | done: true})
      else
        world
      end
    end)
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
    world = %{world | tick: tick, now: now || div(tick, world.p.rate)}

    world
    |> each_second()
    |> step_players()
    |> refresh_walk()
    |> Helpers.step()
    |> refresh_walk()
    |> Workers.step()
    |> take_events()
  end

  @doc "Returns `{world, events}` and removes the events from the world."
  def take_events(%__MODULE__{} = world) do
    {%{world | events: @empty_events}, world.events}
  end

  defp each_second(world) do
    if rem(world.tick, world.p.rate) == 0 do
      world
      |> decay_scent()
      |> pile_loss()
      |> low_workers()
      |> finish_records()
      |> send_records()
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
            scent: false,
            took: nil
        }

        world
        |> put_player(id, player)
        |> event(:you, {id, %{state: "alive", x: x, z: z}})

      {id, %{state: :alive} = player}, world ->
        # The 1.15 lets a client clock be a small quantity faster than the server clock.
        player = %{player | budget: min(@budget_cap, player.budget + world.p.step * 1.15)}
        world = put_player(world, id, player)

        world =
          if player.scent, do: put_scent(world, player.cell, world.p.scent_player), else: world

        touch_pile(world, id, player)

      _, world ->
        world
    end)
  end

  # A player who gets to the pile gets a message, one time for each pile.
  defp touch_pile(world, id, player) do
    pile = world.pile
    {px, pz} = Grid.center(world.grid, pile.cell)

    if player.helper == nil and player.touched != pile.id and
         (player.x - px) ** 2 + (player.z - pz) ** 2 <= world.p.food_touch ** 2 do
      world
      |> put_player(id, %{player | touched: pile.id})
      |> event(:you, {id, %{food: true, pile: pile.id}})
    else
      world
    end
  end

  # ---------------------------------------------------------------------------
  # Values that are calculated from the state

  # After a load: the bodies with no support fall. In a game that runs, no step removes
  # a body, thus no body loses its support.
  defp refresh_structure(world) do
    {supports, fallen} = Support.settle(world.grid, world.rule, world.locked)
    %{world | locked: Map.drop(world.locked, fallen), supports: supports, walk_dirty: true}
  end

  # The number of steps on foot to the nest, for each cell that has a way to the nest.
  defp refresh_walk(%{walk_dirty: false} = world), do: world

  defp refresh_walk(world) do
    nest = world.grid.nest
    walk = flood(world.grid, [nest], %{nest => 0}, 1, :infinity, &walkable?(world, &1))
    pile = world.pile.cell
    reach = 2 * world.p.food_radius
    to_pile = flood(world.grid, [pile], %{pile => 0}, 1, reach, &walkable?(world, &1))

    last =
      for {cell, _} <- world.locked,
          Enum.any?(Grid.neighbors(world.grid, cell), &(Grid.kind(world.grid, &1) == :far)),
          do: cell

    locked? = &is_map_key(world.locked, &1)
    to_far = flood(world.grid, last, Map.new(last, &{&1, 1}), 2, :infinity, locked?)
    %{world | walk: walk, to_pile: to_pile, to_far: to_far, walk_dirty: false}
  end

  # The cells that are not more than `leash` cells from scent or from the nest.
  defp refresh_leash(world) do
    sources = [world.grid.nest | Map.keys(world.scent)]
    start = Map.new(sources, &{&1, 0})
    %{world | leash: flood(world.grid, sources, start, 1, world.p.leash, fn _ -> true end)}
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
