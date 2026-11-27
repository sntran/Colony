defmodule Colony.Workers do
  @moduledoc """
  The rules of the workers.

  A worker never locks. It carries food, and it is a spare body: at a lock, a player takes
  the body of the nearest worker.

  A worker is on one cell. It moves one cell at a time. The speed gives the ticks when a
  worker moves. At each move the worker obeys the first rule that applies:

  1. It carries food: go to the nest by the shortest way.
  2. A pile with food is there, and the worker can walk to it: go to the nearest such pile
     and take one unit.
  3. A pile is there, and no body can walk to it: go to the crossing place and wait there.
  4. Move at random near the nest.

  If rules 2 and 3 apply at the same time, one worker of each three waits at the crossing
  place. The other two carry food.

  At a crossing, some of the workers that waited go to the new pile: see
  `Colony.World`. And until the first food of a pile is at the nest, that pile calls 3
  workers. Such a worker goes to that pile, not to the nearest pile.

  The workers smell the food: no rule reads the scent. A worker with food puts scent, and
  the scent is a picture of the road.
  """

  alias Colony.{Grid, World}

  # A worker that moves at random stays where it is this part of the time.
  @rest_chance 0.5
  # A worker that waits moves to the side this part of the time.
  @shift_chance 0.06
  # Each worker has a different moment in the cycle of the moves.
  @golden 0.6180339887498949

  @doc "Moves each worker that has a move in this tick."
  def step(%World{} = world) do
    tick = world.tick
    step = world.p.step
    world = world |> call_to_piles() |> share_work()

    # `waiting`: the number of workers that wait at each cell.
    waiting =
      Enum.reduce(world.workers, %{}, fn
        {_id, %{mode: :wait, cell: cell}}, acc -> Map.update(acc, cell, 1, &(&1 + 1))
        _, acc -> acc
      end)

    {world, _waiting} =
      Enum.reduce(world.workers, {world, waiting}, fn {id, worker}, {world, waiting} = acc ->
        if moves_now?(id, tick, step), do: decide(world, waiting, id, worker), else: acc
      end)

    world
  end

  # Until the first food of a pile is at the nest, the pile calls workers: 3 workers go
  # to that pile or carry food from it. They are the workers with no food that are
  # nearest to it. Without this rule, the workers go to the nearest pile, and the first
  # food of a far pile comes only when the nearer piles are empty.
  @called 3
  defp call_to_piles(world) do
    Enum.reduce(world.piles, world, fn
      {k, %{fed: false, crossed: crossed, units: units}}, world when crossed != nil and units > 0 ->
        way = Map.fetch!(world.to_pile, k)

        busy =
          Enum.count(world.workers, fn {_id, worker} ->
            worker.mode == {:fetch, k} or worker.carry == k
          end)

        if busy >= @called do
          world
        else
          world.workers
          |> Enum.filter(fn {_id, worker} ->
            worker.carry == nil and not match?({:fetch, _}, worker.mode) and
              is_map_key(way, worker.cell)
          end)
          |> Enum.sort_by(fn {id, worker} -> {Map.fetch!(way, worker.cell), id} end)
          |> Enum.take(@called - busy)
          |> Enum.reduce(world, fn {id, worker}, world ->
            put(world, id, %{worker | mode: {:fetch, k}})
          end)
        end

      _, world ->
        world
    end)
  end

  # While the workers can carry food, one worker of each `wait_part` waits at the crossing
  # place. When a worker must start to wait, it is the worker with no food that is
  # nearest to the crossing place. When a worker must stop, it is the farthest.
  defp share_work(%World{front: front} = world) when front != %{} do
    count = Enum.count(world.workers, fn {_id, worker} -> worker.mode == :wait end)

    wanted =
      if Enum.any?(world.piles, fn {_id, pile} -> pile.units > 0 and pile.crossed != nil end),
        do: ceil(map_size(world.workers) / world.p.wait_part),
        else: map_size(world.workers)

    steps = fn {_id, worker} -> Map.get(front, worker.cell, 1_000_000) end

    changes =
      cond do
        count < wanted ->
          world.workers
          |> Enum.filter(fn {_id, worker} ->
            worker.mode in [:idle, :food] and worker.carry == nil
          end)
          |> Enum.sort_by(&{steps.(&1), elem(&1, 0)})
          |> Enum.take(wanted - count)
          |> Enum.map(fn {id, worker} -> {id, %{worker | mode: :wait}} end)

        count > wanted ->
          world.workers
          |> Enum.filter(fn {_id, worker} -> worker.mode == :wait end)
          |> Enum.sort_by(&{-steps.(&1), elem(&1, 0)})
          |> Enum.take(count - wanted)
          |> Enum.map(fn {id, worker} -> {id, %{worker | mode: :food}} end)

        true ->
          []
      end

    %{world | workers: Enum.into(changes, world.workers)}
  end

  defp share_work(world), do: world

  defp moves_now?(id, tick, step) do
    phase = id * @golden
    phase = phase - Float.floor(phase)
    Float.floor(tick * step + phase) > Float.floor((tick - 1) * step + phase)
  end

  defp decide(world, waiting, id, _worker) do
    # `share_work/1` can change the worker in this tick. Read the worker again.
    worker = Map.fetch!(world.workers, id)
    pile = near_pile(world, worker.cell)

    cond do
      worker.carry != nil ->
        {carry(world, id, worker), waiting}

      match?({:fetch, _}, worker.mode) ->
        {fetch(world, id, worker), waiting}

      world.front != %{} and (worker.mode == :wait or pile == nil) ->
        wait(world, waiting, id, worker)

      pile != nil ->
        {food(world, id, %{worker | mode: :food}, pile), waiting}

      true ->
        {wander(world, id, %{worker | mode: :idle}), waiting}
    end
  end

  # A worker that goes to a new pile after a crossing. If the pile has no food or no way,
  # the worker has no work: the usual rules apply at its next move.
  defp fetch(world, id, %{mode: {:fetch, pile}} = worker) do
    steps = Map.get(Map.fetch!(world.to_pile, pile), worker.cell)

    if steps != nil and Map.fetch!(world.piles, pile).units > 0,
      do: food(world, id, worker, {pile, steps}),
      else: put(world, id, %{worker | mode: :idle})
  end

  # ---------------------------------------------------------------------------
  # Rule 1: carry

  defp carry(world, id, worker) do
    case Map.get(world.walk, worker.cell) do
      nil ->
        # There is no way to the nest. This does not occur: no step removes a locked body.
        world

      distance when distance <= 1 ->
        world
        |> put(id, %{worker | carry: nil, mode: :idle})
        |> World.event(:worker_set, {id, worker.cell, 0})
        |> World.add_nest_food(worker.carry, 1)

      distance ->
        to = nearer(world, world.walk, worker.cell, distance)

        world
        |> move(id, worker, to)
        |> World.add_scent(to, world.p.scent_carry)
    end
  end

  # ---------------------------------------------------------------------------
  # Rule 2: food

  # The nearest pile with food that the worker can walk to: `{pile id, steps}` or nil.
  defp near_pile(world, cell) do
    Enum.reduce(world.piles, nil, fn {id, pile}, best ->
      with true <- pile.units > 0,
           steps when steps != nil <- Map.get(Map.fetch!(world.to_pile, id), cell),
           true <- best == nil or steps < elem(best, 1) do
        {id, steps}
      else
        _ -> best
      end
    end)
  end

  # Goes one step on the shortest way to the pile, or takes one unit.
  defp food(world, id, worker, {pile, steps}) do
    if steps <= 1 do
      {world, 1} = World.take_food(world, pile, 1)

      world
      |> put(id, %{worker | carry: pile, mode: :food})
      |> World.event(:worker_set, {id, worker.cell, 1})
      |> World.add_scent(worker.cell, world.p.scent_carry)
    else
      move(world, id, worker, nearer(world, Map.fetch!(world.to_pile, pile), worker.cell, steps))
    end
  end

  # The cell that is one step nearer. With more than one, the first cell is used. Thus all
  # the workers use the same road.
  defp nearer(world, way, cell, steps) do
    Enum.find(Grid.neighbors(world.grid, cell), &(Map.get(way, &1) == steps - 1))
  end

  # ---------------------------------------------------------------------------
  # Rule 3: wait at the crossing place

  # A worker goes as near to the crossing place as possible. One worker waits on each
  # cell. Thus the workers make a line on the bridge and a crowd behind it.
  defp wait(world, waiting, id, worker) do
    cell = worker.cell
    # A worker that no pile calls starts to wait here.
    waiting = if worker.mode == :wait, do: waiting, else: Map.update(waiting, cell, 1, &(&1 + 1))
    worker = %{worker | mode: :wait}
    world = put(world, id, worker)

    case Map.get(world.front, cell) do
      nil ->
        {world, waiting}

      steps ->
        free = fn to -> Map.get(waiting, to, 0) == 0 end
        around = Grid.neighbors(world.grid, cell)
        ahead = Enum.find(around, &(Map.get(world.front, &1) == steps - 1 and free.(&1)))
        beside = Enum.filter(around, &(Map.get(world.front, &1) == steps and free.(&1)))
        {chance, world} = random(world)

        cond do
          ahead != nil ->
            shift(world, waiting, id, worker, ahead)

          # The cell has a second worker, or the worker moves a little: go to a free cell
          # that is not farther.
          beside != [] and (Map.get(waiting, cell, 0) > 1 or chance < @shift_chance) ->
            {world, to} = pick(world, beside)
            shift(world, waiting, id, worker, to)

          true ->
            {world, waiting}
        end
    end
  end

  defp shift(world, waiting, id, worker, to) do
    waiting =
      waiting
      |> Map.update!(worker.cell, &(&1 - 1))
      |> Map.update(to, 1, &(&1 + 1))

    {move(world, id, worker, to), waiting}
  end

  # ---------------------------------------------------------------------------
  # Rule 4: move at random near the nest

  defp wander(world, id, worker) do
    grid = world.grid
    cell = worker.cell
    world = put(world, id, worker)

    if Grid.nest_distance(grid, cell) > world.p.leash or Grid.land(grid, cell) != 0 or
         Grid.kind(grid, cell) == :gap do
      case Map.get(world.walk, cell) do
        nil -> world
        0 -> world
        steps -> move(world, id, worker, nearer(world, world.walk, cell, steps))
      end
    else
      {rest, world} = random(world)

      cells =
        Enum.filter(Grid.neighbors(grid, cell), fn to ->
          Grid.kind(grid, to) == :land and Grid.nest_distance(grid, to) <= world.p.leash
        end)

      if rest < @rest_chance or cells == [] do
        world
      else
        {world, to} = pick(world, cells)
        move(world, id, worker, to)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers

  defp put(world, id, worker), do: %{world | workers: Map.put(world.workers, id, worker)}

  defp move(world, id, worker, to) do
    direction = Grid.direction(world.grid, worker.cell, to)

    %{world | workers: Map.put(world.workers, id, %{worker | cell: to})}
    |> World.cross(to)
    |> World.event(:moves, {id, direction})
  end

  defp random(world) do
    {value, rng} = :rand.uniform_s(world.rng)
    {value, %{world | rng: rng}}
  end

  defp pick(world, [one]), do: {world, one}

  defp pick(world, cells) do
    {n, rng} = :rand.uniform_s(length(cells), world.rng)
    {%{world | rng: rng}, Enum.at(cells, n - 1)}
  end
end
