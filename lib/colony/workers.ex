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

    # `waiting`: the number of workers that wait at each cell.
    waiting =
      Enum.reduce(world.workers, %{}, fn
        {_id, %{mode: :wait, cell: cell}}, acc -> Map.update(acc, cell, 1, &(&1 + 1))
        _, acc -> acc
      end)

    state = %{waiting: waiting, count: waiting |> Map.values() |> Enum.sum()}

    {world, _state} =
      Enum.reduce(world.workers, {world, state}, fn {id, worker}, {world, state} = acc ->
        if moves_now?(id, tick, step), do: decide(world, state, id, worker), else: acc
      end)

    world
  end

  defp moves_now?(id, tick, step) do
    phase = id * @golden
    phase = phase - Float.floor(phase)
    Float.floor(tick * step + phase) > Float.floor((tick - 1) * step + phase)
  end

  defp decide(world, state, id, %{carry: carry} = worker) when carry != nil do
    {carry(world, id, worker), state}
  end

  defp decide(world, state, id, worker) do
    pile = near_pile(world, worker.cell)
    place? = world.front != %{}

    cond do
      pile != nil and place? ->
        {worker, state} = pick_work(world, state, worker)

        if worker.mode == :wait,
          do: wait(world, state, id, worker),
          else: {food(world, id, worker, pile), state}

      pile != nil ->
        {food(world, id, %{worker | mode: :food}, pile), leave_wait(state, worker)}

      place? ->
        wait(world, join_wait(state, worker), id, %{worker | mode: :wait})

      true ->
        {wander(world, id, %{worker | mode: :idle}), leave_wait(state, worker)}
    end
  end

  # One worker of each `wait_part` waits. The other workers carry food.
  defp pick_work(world, state, worker) do
    wanted = ceil(map_size(world.workers) / world.p.wait_part)

    cond do
      worker.mode == :wait and state.count > wanted ->
        {%{worker | mode: :food}, leave_wait(state, worker)}

      worker.mode != :wait and state.count < wanted ->
        {%{worker | mode: :wait}, join_wait(state, worker)}

      worker.mode == :wait ->
        {worker, state}

      true ->
        {%{worker | mode: :food}, state}
    end
  end

  defp join_wait(state, %{mode: :wait}), do: state

  defp join_wait(state, worker) do
    %{waiting: Map.update(state.waiting, worker.cell, 1, &(&1 + 1)), count: state.count + 1}
  end

  defp leave_wait(state, %{mode: :wait} = worker) do
    %{waiting: Map.update!(state.waiting, worker.cell, &(&1 - 1)), count: state.count - 1}
  end

  defp leave_wait(state, _worker), do: state

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
  defp wait(world, state, id, worker) do
    cell = worker.cell
    world = put(world, id, worker)

    case Map.get(world.front, cell) do
      nil ->
        {world, state}

      steps ->
        free = fn to -> Map.get(state.waiting, to, 0) == 0 end
        around = Grid.neighbors(world.grid, cell)
        ahead = Enum.find(around, &(Map.get(world.front, &1) == steps - 1 and free.(&1)))
        beside = Enum.filter(around, &(Map.get(world.front, &1) == steps and free.(&1)))
        {chance, world} = random(world)

        cond do
          ahead != nil ->
            shift(world, state, id, worker, ahead)

          # The cell has a second worker, or the worker moves a little: go to a free cell
          # that is not farther.
          beside != [] and (Map.get(state.waiting, cell, 0) > 1 or chance < @shift_chance) ->
            {world, to} = pick(world, beside)
            shift(world, state, id, worker, to)

          true ->
            {world, state}
        end
    end
  end

  defp shift(world, state, id, worker, to) do
    waiting =
      state.waiting
      |> Map.update!(worker.cell, &(&1 - 1))
      |> Map.update(to, 1, &(&1 + 1))

    {move(world, id, worker, to), %{state | waiting: waiting}}
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
