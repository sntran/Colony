defmodule Colony.World do
  @moduledoc """
  The state of the world and the rules that change it.

  This module has no processes and no clock. `tick/2` moves the world one step. The server
  process calls it 10 times each second. The tests call it as fast as possible.

  Each change that a client must know is added to `events`. `tick/2` returns the events of
  the step and removes them from the world.

  The rules of plan 0004:

  - The world has rivers, one after the other. The colony builds one bridge for each river.
  - Only a player or a helper locks, and only into an open cell. A worker never locks.
  - The colony has two kinds of workers. A carrier carries food. A spare body waits at the
    crossing place. A lock uses one spare body, never a carrier.
  - A player who carries food cannot lock.
  - A crossing is the moment when a bridge touches the next land. It makes a record, the
    nest moves to the foot of the new bridge, and the next pile appears.
  - The food of pile `k` makes the spare bodies for the bridge across river `k + 1`.
  - A person is the same person for always: the page gives a secret number at each join.
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
            # Workers: id => %{cell, kind, carry, mode}. `kind` is :carrier or :spare.
            # `carry` is nil, the number of a pile, or :egg. The mode of a carrier is :idle,
            # :food, {:egg, :fetch} or {:egg, :bring}. The mode of a spare body is :wait
            # or :idle.
            workers: %{},
            # The number of workers of each kind.
            counts: %{carrier: 0, spare: 0},
            # Worker numbers that are free for a new worker.
            free_ids: [],
            # Worker numbers that are free from the next tick. A client gets "worker gone"
            # and "worker set" of one number in two different messages.
            freed_ids: [],
            next_worker: 0,
            # Locked bodies: cell => %{name, helper, owner, time, n, crossings}. `owner` is
            # the number of the person, or nil for a helper. `n` is the number of the lock
            # in the story, from 1.
            locked: %{},
            # Support of the locked bodies: cell => support, as an integer.
            supports: %{},
            lock_count: 0,
            # Scent: cell => 1..100. It is a picture of the road. No rule reads it.
            scent: %{},
            # The piles of food: id => %{id, cell, col, size, least, units, appeared,
            # crossed, fed}. Pile `k` is on land `k`.
            piles: %{},
            # The river that the colony builds a bridge across now. In a world with an end,
            # after the last crossing, it is the number of rivers plus 1.
            stage: 1,
            # The open cells of the river `stage`: cell => gain.
            open: %{},
            # The time of the first lock of each bridge: river => time.
            first_lock: %{},
            # The cell of the nest. The nest moves at each crossing.
            nest: nil,
            # The nests before this one, the newest first: %{cell, land}.
            old_nests: [],
            food_nest: 0,
            # Units of food that count for the next new spare body.
            food_credit: 0,
            # The tick of the last spare body that the nest made because the colony had few.
            low_tick: 0,
            # Players and helpers: id => player.
            players: %{},
            next_player: 1,
            # The persons: number => %{name, food, secret}. `secret` is the SHA-256 of the
            # secret number of the page, or nil.
            people: %{},
            # The SHA-256 of a secret number => the number of its person.
            secrets: %{},
            next_person: 1,
            # The food that each helper carried to the nest: name => units.
            helper_food: %{},
            # The food that each person or helper carried since the last crossing:
            # {:person, number} or {:helper, name} => units.
            period: %{},
            # The number of steps on foot from each cell to the nest.
            walk: %{},
            # For each pile with food: the number of steps on foot from each cell to the pile.
            to_pile: %{},
            # The number of steps on foot from each cell to the crossing place.
            front: %{},
            # While carriers carry eggs: the number of steps on foot to the old nest.
            to_old_nest: %{},
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
    people: [],
    you: [],
    records: [],
    # The locked bodies whose support changed.
    structure: [],
    # The piles that changed.
    piles: [],
    open: false,
    food: false,
    nest: false
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
    grid = Grid.new(cfg, seed, saved && saved.rivers)

    p = %{
      rate: rate,
      step: Keyword.fetch!(cfg, :speed) / rate,
      leash: Keyword.fetch!(cfg, :leash),
      food_touch: Keyword.fetch!(cfg, :food_touch),
      nest_touch: Keyword.fetch!(cfg, :nest_touch),
      nest_rows: Keyword.fetch!(cfg, :nest_rows),
      player_food: Keyword.fetch!(cfg, :player_food),
      pile_rows: Keyword.fetch!(cfg, :pile_rows_from_river),
      pile_first_columns: Keyword.fetch!(cfg, :pile_first_columns),
      pile_shift_columns: Keyword.fetch!(cfg, :pile_shift_columns),
      pile_edge_columns: Keyword.fetch!(cfg, :pile_edge_columns),
      pile_loss: Keyword.fetch!(cfg, :pile_loss_seconds),
      pile_factor: Keyword.fetch!(cfg, :pile_factor),
      pile_least_factor: Keyword.fetch!(cfg, :pile_least_factor),
      last_pile_units: Keyword.fetch!(cfg, :last_pile_units),
      last_pile_least: Keyword.fetch!(cfg, :last_pile_least),
      bridge_best: Keyword.fetch!(cfg, :bridge_best),
      bridge_random: Keyword.fetch!(cfg, :bridge_random),
      start_columns: Keyword.fetch!(cfg, :start_columns),
      takeover_ticks: round(Keyword.fetch!(cfg, :takeover_seconds) * rate),
      carriers: Keyword.fetch!(cfg, :carriers),
      carriers_per_crossing: Keyword.fetch!(cfg, :carriers_per_crossing),
      carriers_max: Keyword.fetch!(cfg, :carriers_max),
      spare: Keyword.fetch!(cfg, :spare),
      spare_max: Keyword.fetch!(cfg, :spare_max),
      food_per_body: Keyword.fetch!(cfg, :food_per_body),
      spare_low: Keyword.fetch!(cfg, :spare_low),
      spare_ticks: Keyword.fetch!(cfg, :spare_seconds) * rate,
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
      nest: grid.nest,
      events: @empty_events
    }

    counts =
      (saved && Map.get(saved, :workers)) || %{carrier: p.carriers, spare: p.spare}

    world
    |> restore(saved)
    |> place_workers(:carrier, counts.carrier)
    |> place_workers(:spare, counts.spare)
    |> refresh_structure()
    |> refresh_ways()
    |> set_helpers(p.helpers)
  end

  # ---------------------------------------------------------------------------
  # Save and load

  @doc "The version of the save file. A file with a different version is not loaded."
  def save_version, do: 5

  @doc "The part of the world that goes into the save file."
  def to_save(%__MODULE__{} = world) do
    %{
      version: save_version(),
      seed: world.seed,
      rivers: Grid.river_count(world.grid),
      start: world.start,
      locked:
        world.locked
        |> Enum.map(fn {cell, body} ->
          {cell, body.name, body.helper, body.owner, body.time, body.n, body.crossings}
        end)
        |> Enum.sort(),
      lock_count: world.lock_count,
      scent: world.scent,
      piles: world.piles,
      stage: world.stage,
      first_lock: world.first_lock,
      nest: world.nest,
      old_nests: world.old_nests,
      food_nest: world.food_nest,
      food_credit: world.food_credit,
      workers: world.counts,
      people: world.people,
      next_person: world.next_person,
      helper_food: world.helper_food,
      period: world.period,
      records: world.records,
      complete: world.complete
    }
  end

  defp restore(world, %{version: 5} = saved) do
    grid = world.grid

    # A saved cell is used only if it is a river cell of this grid. The config can change
    # between two runs.
    locked =
      for {cell, name, helper, owner, time, n, crossings} <- saved.locked,
          cell < grid.count and Grid.kind(grid, cell) == :gap,
          into: %{} do
        {cell, %{name: name, helper: helper, owner: owner, time: time, n: n, crossings: crossings}}
      end

    secrets =
      for {number, %{secret: secret}} <- saved.people, secret != nil, into: %{} do
        {secret, number}
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
        nest: saved.nest,
        old_nests: saved.old_nests,
        food_nest: saved.food_nest,
        food_credit: saved.food_credit,
        people: saved.people,
        secrets: secrets,
        next_person: saved.next_person,
        helper_food: saved.helper_food,
        period: saved.period,
        records: saved.records,
        complete: saved.complete
    }
  end

  # No file, or a file of an older version of the game: a new world.
  defp restore(world, _saved), do: add_pile(world, 1)

  # The workers start near the nest.
  defp place_workers(world, kind, count) do
    spots =
      world.grid.count
      |> then(&(0..(&1 - 1)))
      |> Enum.filter(fn cell ->
        Grid.kind(world.grid, cell) == :land and Grid.distance(world.grid, cell, world.nest) <= 3
      end)
      |> List.to_tuple()

    Enum.reduce(1..count//1, world, fn _, world ->
      {n, rng} = :rand.uniform_s(tuple_size(spots), world.rng)
      add_worker(%{world | rng: rng}, kind, elem(spots, n - 1), false)
    end)
  end

  # ---------------------------------------------------------------------------
  # Players

  @doc """
  Adds a player. The player gets a body at the nest. This body does not use a spare body.

  `secret` is the secret number of the page, as text, or nil. A second join with the same
  secret number is the same person: the name of that person changes to `name`.

  Returns `{world, id}`.
  """
  def join(%__MODULE__{} = world, name, secret \\ nil) do
    {world, person} = person(world, name, secret)
    add_body(world, name, nil, person)
  end

  # The number of the person with this secret number, or a new person.
  defp person(world, name, secret) do
    hash = secret && :crypto.hash(:sha256, secret)

    case hash && Map.get(world.secrets, hash) do
      nil ->
        number = world.next_person
        entry = %{name: name, food: 0, secret: hash}

        world = %{
          world
          | people: Map.put(world.people, number, entry),
            secrets: if(hash, do: Map.put(world.secrets, hash, number), else: world.secrets),
            next_person: number + 1
        }

        {world, number}

      number ->
        {rename_person(world, number, name), number}
    end
  end

  defp add_body(world, name, helper, person) do
    id = free_player_id(world, world.next_player)
    {x, z} = Grid.center(world.grid, world.nest)

    player = %{
      name: name,
      x: x,
      z: z,
      heading: 0.0,
      cell: world.nest,
      budget: @budget_cap,
      # The food that the body carries: nil or %{pile, units}.
      carry: nil,
      # The body can lock from this tick.
      ready_tick: 0,
      # The worker whose body the player took at the last lock.
      took: nil,
      # The last act of the player: nil, :lock or :carry. The guide uses it.
      last: nil,
      # The number of the person, or nil for a helper.
      person: person,
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
  A player gets a new name. The person keeps the bodies and the food: all the bodies of
  the person, the records and the story get the new name.
  """
  def rename(%__MODULE__{} = world, id, name) do
    case world.players do
      %{^id => %{helper: nil, person: person}} -> rename_person(world, person, name)
      _ -> world
    end
  end

  defp rename_person(world, person, name) do
    world = %{world | people: Map.update!(world.people, person, &%{&1 | name: name})}

    players =
      Map.new(world.players, fn
        {id, %{person: ^person} = player} -> {id, %{player | name: name}}
        entry -> entry
      end)

    locked =
      Map.new(world.locked, fn
        {cell, %{owner: ^person} = body} -> {cell, %{body | name: name}}
        entry -> entry
      end)

    {records, dirty} =
      Enum.map_reduce(world.records, world.records_dirty, fn record, dirty ->
        if Enum.any?(record.names, &(&1.owner == person)) do
          names =
            for entry <- record.names do
              if entry.owner == person, do: %{entry | name: name}, else: entry
            end

          {%{record | names: names}, Enum.uniq([record.id | dirty])}
        else
          {record, dirty}
        end
      end)

    world = %{world | players: players, locked: locked, records: records, records_dirty: dirty}

    world =
      Enum.reduce(players, world, fn
        {id, %{person: ^person}}, world -> event(world, :names, {id, name, false})
        _, world -> world
      end)

    event(world, :people, {person, name})
  end

  @doc "Removes a player. The locked bodies of the player stay."
  def leave(%__MODULE__{} = world, id) do
    %{world | players: Map.delete(world.players, id)}
  end

  @doc "The number of persons in the world: players that are not helpers."
  def persons(%__MODULE__{} = world) do
    Enum.count(world.players, fn {_id, player} -> player.helper == nil end)
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

  A lock is possible only into an open cell that touches the cell of the body, only if the
  colony has a spare body, and only if the body carries no food. The player then takes
  the body of the nearest spare body.

  Returns `{:ok, world}` or `{{:error, reason}, world}`.
  """
  def lock(%__MODULE__{} = world, id, cell) do
    with %{} = player <- Map.get(world.players, id),
         true <- world.tick >= player.ready_tick,
         true <- is_integer(cell) and cell >= 0 and cell < world.grid.count,
         true <- cell in Grid.neighbors(world.grid, player.cell),
         true <- is_map_key(world.open, cell),
         true <- player.carry == nil,
         true <- world.counts.spare > 0 do
      river = world.stage

      body = %{
        name: player.name,
        helper: player.helper != nil,
        owner: player.person,
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
    river = Grid.river(world.grid, cell)
    # A lock changes the supports of its bridge only.
    group = Support.with_body(world.grid, world.rule, world.locked, cell)
    locked = Map.put(world.locked, cell, body)

    world = %{
      world
      | locked: locked,
        lock_count: body.n,
        supports: Map.merge(world.supports, group),
        first_lock: Map.put_new(world.first_lock, river, world.now)
    }

    # A body can walk on the new cell. The ways to the nest and to the piles change.
    %{
      world
      | walk: add_to_way(world, world.walk, cell),
        to_pile: Map.new(world.to_pile, fn {pile, way} -> {pile, add_to_way(world, way, cell)} end)
    }
    |> event(:locks, {cell, body, id})
    |> changed_supports(Map.keys(group))
  end

  defp changed_supports(world, cells) do
    %{world | events: %{world.events | structure: cells ++ world.events.structure}}
  end

  # The player gets the body of the spare body that is nearest to the locked body by
  # steps on foot. A carrier is never used.
  defp take_body(world, id, player, cell) do
    {worker_id, at} =
      nearest_worker(world, cell, &(&1.kind == :spare)) || any_spare(world)

    {x, z} = Grid.center(world.grid, at)

    player = %{
      player
      | x: x,
        z: z,
        cell: at,
        budget: @budget_cap,
        ready_tick: world.tick + world.p.takeover_ticks,
        took: worker_id,
        last: :lock
    }

    %{world | players: Map.put(world.players, id, player)}
    |> remove_worker(worker_id)
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

  # A spare body that no way on foot gets to. This does not occur in a game that runs.
  defp any_spare(world) do
    {id, worker} = world.workers |> Enum.filter(fn {_id, w} -> w.kind == :spare end) |> Enum.min()
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
        {world, _id} = add_body(world, "Helper #{n}", Helpers.new(n), nil)
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
  def open?(world, cell), do: is_map_key(world.open, cell)

  @doc "The number of spare bodies."
  def spare(world), do: world.counts.spare

  @doc "The number of carriers."
  def carriers(world), do: world.counts.carrier

  @doc "The number of rivers of the grid."
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

  @doc "The piles with food that a body at the nest can walk to."
  def food_piles(world) do
    for {id, pile} <- world.piles,
        pile.units > 0,
        way = Map.get(world.to_pile, id),
        way != nil and is_map_key(way, world.nest),
        do: pile
  end

  @doc "The name of a person or of a helper: {:person, number} or {:helper, name}."
  def who(%{helper: nil, person: person}), do: {:person, person}
  def who(%{name: name}), do: {:helper, name}

  @doc """
  The numbers of a person: the locked bodies, the food that the person carried to the
  nest, and the number of times that a worker or a player walked on a body of the person.
  """
  def person_numbers(%__MODULE__{} = world, person) do
    {bodies, walks} =
      Enum.reduce(world.locked, {0, 0}, fn
        {_cell, %{owner: ^person, crossings: crossings}}, {bodies, walks} ->
          {bodies + 1, walks + crossings}

        _, acc ->
          acc
      end)

    entry = Map.get(world.people, person, %{name: "", food: 0})
    %{person: person, name: entry.name, bodies: bodies, food: entry.food, walks: walks}
  end

  @doc """
  The story: all the locks in the order of their times, and the players with their bodies,
  their food and the walks on their bodies.
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
          owner: body.owner,
          time: body.time
        }
      end)

    counts =
      Enum.reduce(world.locked, %{}, fn {_cell, body}, acc ->
        key = if body.helper, do: {:helper, body.name}, else: {:person, body.owner}
        Map.update(acc, key, {1, body.crossings}, fn {n, w} -> {n + 1, w + body.crossings} end)
      end)

    people =
      for {number, entry} <- world.people, into: %{} do
        {{:person, number}, %{name: entry.name, helper: false, owner: number, food: entry.food}}
      end

    helpers =
      for {name, food} <- world.helper_food, into: %{} do
        {{:helper, name}, %{name: name, helper: true, owner: nil, food: food}}
      end

    names =
      for key <- Enum.uniq(Map.keys(counts) ++ Map.keys(people) ++ Map.keys(helpers)),
          entry = Map.get(people, key) || Map.get(helpers, key) || helper_entry(key),
          {bodies, walks} = Map.get(counts, key, {0, 0}),
          bodies > 0 or entry.food > 0 do
        Map.merge(entry, %{bodies: bodies, walks: walks})
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

  defp helper_entry({:helper, name}), do: %{name: name, helper: true, owner: nil, food: 0}
  defp helper_entry(_key), do: nil

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
    pile = %{pile | units: pile.units - units}
    world = %{world | piles: Map.put(world.piles, pile_id, pile)}

    # A pile with no food needs no map of the way to it.
    world =
      if pile.units == 0, do: %{world | to_pile: Map.delete(world.to_pile, pile_id)}, else: world

    {event(world, :piles, pile_id), units}
  end

  @doc false
  # Units of food from the pile `pile_id` get to the nest. `by` is the player that carried
  # them, or nil for a carrier.
  def add_nest_food(world, pile_id, units, by \\ nil) do
    world = flag(%{world | food_nest: world.food_nest + units}, :food)
    world = make_spare(%{world | food_credit: world.food_credit + units})
    world = %{world | piles: Map.update!(world.piles, pile_id, &%{&1 | fed: true})}

    world =
      case by do
        nil ->
          world

        player ->
          key = who(player)

          world =
            case key do
              {:person, number} ->
                %{world | people: Map.update!(world.people, number, &%{&1 | food: &1.food + units})}

              {:helper, name} ->
                %{world | helper_food: Map.update(world.helper_food, name, units, &(&1 + units))}
            end

          %{world | period: Map.update(world.period, key, units, &(&1 + units))}
          |> count_last_record(player, key, units)
      end

    # In a world with an end, the first food of the last pile makes the world complete.
    if world.complete == nil and not Grid.endless?(world.cfg) and pile_id == rivers(world) do
      flag(%{world | complete: world.now}, :food)
    else
      world
    end
  end

  @doc false
  def put_player(world, id, player), do: %{world | players: Map.put(world.players, id, player)}

  # ---------------------------------------------------------------------------
  # Workers

  # Adds a worker of a kind on a cell. `jump` tells the clients that the worker starts
  # at a new position.
  defp add_worker(world, kind, cell, jump \\ true) do
    {id, world} =
      case world.free_ids do
        [id | rest] -> {id, %{world | free_ids: rest}}
        [] -> {world.next_worker, %{world | next_worker: world.next_worker + 1}}
      end

    mode = if kind == :spare, do: :wait, else: :idle
    worker = %{cell: cell, kind: kind, carry: nil, mode: mode}

    world = %{
      world
      | workers: Map.put(world.workers, id, worker),
        counts: Map.update!(world.counts, kind, &(&1 + 1))
    }

    if jump, do: event(world, :worker_set, {id, cell, flags(worker) + 2}), else: world
  end

  defp remove_worker(world, id) do
    worker = Map.fetch!(world.workers, id)

    %{
      world
      | workers: Map.delete(world.workers, id),
        counts: Map.update!(world.counts, worker.kind, &(&1 - 1)),
        freed_ids: [id | world.freed_ids]
    }
    |> event(:worker_gone, id)
  end

  @doc false
  # The flags of a worker in a message: 1 = carries food, 4 = carries an egg, 8 = carrier.
  def flags(worker) do
    carry =
      case worker.carry do
        nil -> 0
        :egg -> 4
        _ -> 1
      end

    carry + if(worker.kind == :carrier, do: 8, else: 0)
  end

  # The nest makes one spare body for each `food_per_body` units of food.
  defp make_spare(world) do
    if world.food_credit >= world.p.food_per_body and world.counts.spare < world.p.spare_max do
      world = %{world | food_credit: world.food_credit - world.p.food_per_body}
      make_spare(add_worker(world, :spare, world.nest))
    else
      %{world | food_credit: min(world.food_credit, world.p.food_per_body)}
    end
  end

  # With few spare bodies and no pile with food that a body can walk to, the nest makes
  # one spare body each some seconds.
  defp low_help(world) do
    cond do
      world.counts.spare >= world.p.spare_low or food_piles(world) != [] ->
        %{world | low_tick: world.tick}

      world.tick - world.low_tick >= world.p.spare_ticks ->
        add_worker(%{world | low_tick: world.tick}, :spare, world.nest)

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
    {size, least} = pile_size(world, k)

    pile = %{
      id: k,
      cell: cell,
      col: col,
      size: size,
      # The pile does not lose units below this number.
      least: least,
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
    |> event(:piles, k)
  end

  @doc """
  The size of pile `k` and the least number of its units: `{size, least}`.

  Pile `k` pays for the bridge across river `k + 1`. With `R` the highest "Random" and `B`
  "Best" of the table of the open cells for the largest width of that river, the size is
  `food_per_body * pile_factor * R` and the least is `food_per_body * pile_least_factor * B`.
  The last pile of a world with an end has numbers of its own.
  """
  def pile_size(world, k) do
    p = world.p

    case Grid.limits(world.cfg, k + 1) do
      nil ->
        {p.last_pile_units, p.last_pile_least}

      {_least, most} ->
        r = Map.fetch!(p.bridge_random, most)
        b = Map.fetch!(p.bridge_best, most)

        {round(p.food_per_body * p.pile_factor * r),
         round(p.food_per_body * p.pile_least_factor * b)}
    end
  end

  # Pile 1 is near the column of the nest. Each later pile is 12 columns or less from the
  # pile before it, and not near an edge of the world.
  defp pile_column(world, k) do
    grid = world.grid
    last = grid.width - 1
    margin = min(world.p.pile_edge_columns, div(last, 2))

    {low, high} =
      case Map.get(world.piles, k - 1) do
        nil ->
          nest_col = Grid.col(grid, world.nest)

          {max(0, nest_col - world.p.pile_first_columns),
           min(last, nest_col + world.p.pile_first_columns)}

        before ->
          shift = world.p.pile_shift_columns
          {max(margin, before.col - shift), min(last - margin, before.col + shift)}
      end

    {n, rng} = :rand.uniform_s(high - low + 1, world.rng)
    {low + n - 1, %{world | rng: rng}}
  end

  # A pile that no body can walk to loses units, down to its least number.
  defp pile_loss(world) do
    with true <- rem(div(world.tick, world.p.rate), world.p.pile_loss) == 0,
         %{units: units, least: least} = pile when units > least <- far_pile(world) do
      event(
        %{world | piles: Map.put(world.piles, pile.id, %{pile | units: units - 1})},
        :piles,
        pile.id
      )
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
    world = event(world, :piles, k)
    world = make_record(world, k, pile)
    world = %{world | period: %{}}
    world = move_nest(world, k)
    world = if Grid.limits(world.cfg, k + 1), do: add_pile(world, k + 1), else: world
    flag(world, :food)
  end

  # The nest moves to the foot of the new bridge: some rows south of its first body. The
  # colony gets new carriers there. The carriers with no food carry eggs from the old
  # nest to the new nest.
  defp move_nest(world, k) do
    grid = world.grid

    {first, _body} =
      world.locked
      |> Enum.filter(fn {cell, _} -> Grid.river(grid, cell) == k end)
      |> Enum.min_by(fn {_, body} -> body.n end)

    old = world.nest
    # A small grid can have fewer rows south of the bridge: the row is 0 or more.
    row = max(0, Grid.row(grid, first) - world.p.nest_rows)
    nest = nest_cell(world, Grid.cell(grid, row, Grid.col(grid, first)))

    world = %{
      world
      | nest: nest,
        old_nests: [%{cell: old, land: Grid.land(grid, old)} | world.old_nests]
    }

    world =
      Enum.reduce(1..world.p.carriers_per_crossing//1, world, fn _, world ->
        if world.counts.carrier < world.p.carriers_max,
          do: add_worker(world, :carrier, nest),
          else: world
      end)

    # The new carriers stay. Each older carrier with no food goes to the old nest for an egg.
    workers =
      Map.new(world.workers, fn
        {id, %{kind: :carrier, carry: nil, cell: cell} = worker} when cell != nest ->
          {id, %{worker | mode: {:egg, :fetch}}}

        entry ->
          entry
      end)

    to_old = flood(grid, [old], %{old => 0}, 1, :infinity, &walkable?(world, &1))

    %{world | workers: workers, to_old_nest: to_old}
    |> refresh_walk()
    |> flag(:nest)
  end

  # The cell for the nest: the cell itself if it is a land cell with no pile, or the
  # nearest such cell.
  defp nest_cell(world, cell) do
    grid = world.grid
    piles = MapSet.new(world.piles, fn {_id, pile} -> pile.cell end)
    free? = &(Grid.kind(grid, &1) == :land and not MapSet.member?(piles, &1))

    if free?.(cell) do
      cell
    else
      0..(grid.count - 1)
      |> Enum.filter(free?)
      |> Enum.min_by(&{Grid.distance(grid, &1, cell), &1})
    end
  end

  @doc "The number of bodies of the best bridge across a river of a width, from the table."
  def best_bodies(world, width), do: Map.get(world.p.bridge_best, width)

  defp make_record(world, k, pile) do
    grid = world.grid
    cells = bridge(world, k)
    width = cells |> Enum.map(&Grid.river_width(grid, k, Grid.col(grid, &1))) |> Enum.max()

    bodies =
      cells
      |> Enum.map(&Map.fetch!(world.locked, &1))
      |> Enum.frequencies_by(fn body ->
        if body.helper, do: {:helper, body.name}, else: {:person, body.owner}
      end)

    record = %{
      id: k,
      time: world.now,
      # The seconds from the first lock of the bridge to the crossing.
      seconds: max(0, world.now - Map.get(world.first_lock, k, world.now)),
      names: record_names(world, bodies, world.period),
      bodies: length(cells),
      rows: cells |> Enum.map(&Grid.row(grid, &1)) |> Enum.uniq() |> length(),
      # The width of the river in the widest column of the bridge, and the bodies of the
      # best bridge across a river of that width.
      width: width,
      best: best_bodies(world, width),
      # The units of the pile at the crossing, and its units at the start.
      left: pile.units,
      size: pile.size
    }

    %{world | records: [record | world.records]}
    # Each player sees this record immediately.
    |> event(:records, Map.put(record, :first, true))
  end

  defp record_names(world, bodies, food) do
    for key <- Enum.uniq(Map.keys(bodies) ++ Map.keys(food)) do
      entry(world, key, Map.get(bodies, key, 0), Map.get(food, key, 0))
    end
    |> Enum.sort_by(&{-&1.bodies, -&1.food, &1.name})
  end

  defp entry(world, {:person, number}, bodies, food) do
    name = world.people |> Map.get(number, %{name: ""}) |> Map.fetch!(:name)
    %{name: name, helper: false, owner: number, bodies: bodies, food: food}
  end

  defp entry(_world, {:helper, name}, bodies, food) do
    %{name: name, helper: true, owner: nil, bodies: bodies, food: food}
  end

  # After the last crossing of a world with an end, the food that a player carries counts
  # in the last record.
  defp count_last_record(world, _player, key, units) do
    with true <- world.stage > rivers(world) and not Grid.endless?(world.cfg),
         [record | rest] <- world.records do
      same? = fn entry ->
        entry(world, key, 0, 0) |> Map.take([:name, :helper, :owner]) ==
          Map.take(entry, [:name, :helper, :owner])
      end

      names =
        case Enum.split_with(record.names, same?) do
          {[entry], others} -> [%{entry | food: entry.food + units} | others]
          {[], others} -> [entry(world, key, 0, units) | others]
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
      |> low_help()
      |> send_records()
      |> end_eggs()
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

  # When no carrier goes for an egg, the map of the way to the old nest is not necessary.
  defp end_eggs(%{to_old_nest: way} = world) when way == %{}, do: world

  defp end_eggs(world) do
    if Enum.any?(world.workers, fn {_id, worker} -> worker.mode == {:egg, :fetch} end),
      do: world,
      else: %{world | to_old_nest: %{}}
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
    if player.helper == nil or player.helper.goal == :pile do
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
    if near?(world, player, world.nest, world.p.nest_touch) do
      world
      |> put_player(id, %{player | carry: nil, last: :carry})
      |> add_nest_food(carry.pile, carry.units, player)
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
    open? = &walkable?(world, &1)

    to_pile =
      for {id, pile} <- world.piles, pile.units > 0, into: %{} do
        {id, flood(world.grid, [pile.cell], %{pile.cell => 0}, 1, :infinity, open?)}
      end

    %{world | to_pile: to_pile}
    |> refresh_walk()
    |> refresh_open()
    |> refresh_front()
  end

  # The number of steps on foot to the nest, for each cell that has a way to the nest.
  defp refresh_walk(world) do
    nest = world.nest
    walk = flood(world.grid, [nest], %{nest => 0}, 1, :infinity, &walkable?(world, &1))
    %{world | walk: walk}
  end

  # The open cells of the river that the colony builds a bridge across now.
  defp refresh_open(world) do
    case far_pile(world) do
      nil ->
        flag(%{world | open: %{}}, :open)

      pile ->
        grid = world.grid
        row = Grid.river_start(grid, pile.id)

        start =
          for col <- 0..(grid.width - 1),
              abs(col - pile.col) <= world.p.start_columns,
              do: Grid.cell(grid, row, col)

        open = Support.open_gains(grid, world.rule, world.locked, pile.id, start)
        flag(%{world | open: Map.new(open)}, :open)
    end
  end

  # The number of steps on foot to the crossing place: the cells where a body can stand
  # and lock into an open cell. With no bridge, these are the cells at the edge of the
  # land, near the column of the pile. With a bridge, they are bodies of the bridge.
  defp refresh_front(world) do
    sources =
      for {cell, _gain} <- world.open,
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
