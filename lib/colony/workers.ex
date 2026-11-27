defmodule Colony.Workers do
  @moduledoc """
  The rules of the workers.

  A worker never locks. The colony has two kinds of workers:

  - **A carrier** carries food. A lock never uses a carrier. At each move a carrier obeys
    the first rule that applies:
    1. It carries an egg: go to the nest and put the egg there.
    2. It carries food: go to the nest by the shortest way.
    3. It goes for an egg: go to the old nest and take an egg.
    4. A pile with food is there, and the carrier can walk to it: go to the nearest such
       pile and take one unit.
    5. Move at random near the nest.
  - **A spare body** waits at the crossing place: a lock uses the nearest spare body. With
    no open cell, a spare body moves at random near the nest.

  A worker is on one cell. It moves one cell at a time. The speed gives the ticks when a
  worker moves.

  The workers smell the food: no rule reads the scent. A carrier with food puts scent, and
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

    # `waiting`: the number of spare bodies that wait at each cell.
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

  defp moves_now?(id, tick, step) do
    phase = id * @golden
    phase = phase - Float.floor(phase)
    Float.floor(tick * step + phase) > Float.floor((tick - 1) * step + phase)
  end

  defp decide(world, waiting, id, %{kind: :spare} = worker) do
    if world.front != %{} do
      wait(world, waiting, id, worker)
    else
      waiting =
        if worker.mode == :wait, do: Map.update(waiting, worker.cell, 0, &(&1 - 1)), else: waiting

      {wander(world, id, %{worker | mode: :idle}), waiting}
    end
  end

  defp decide(world, waiting, id, worker) do
    world =
      cond do
        worker.carry == :egg ->
          bring_egg(world, id, worker)

        worker.carry != nil ->
          carry(world, id, worker)

        worker.mode == {:egg, :fetch} ->
          fetch_egg(world, id, worker)

        (pile = near_pile(world, worker.cell)) != nil ->
          food(world, id, %{worker | mode: :food}, pile)

        true ->
          wander(world, id, %{worker | mode: :idle})
      end

    {world, waiting}
  end

  # ---------------------------------------------------------------------------
  # Eggs: after the nest moved, a carrier takes an egg from the old nest to the new nest.

  defp fetch_egg(world, id, worker) do
    case Map.get(world.to_old_nest, worker.cell) do
      nil ->
        put(world, id, %{worker | mode: :idle})

      steps when steps <= 1 ->
        worker = %{worker | carry: :egg, mode: {:egg, :bring}}

        world
        |> put(id, worker)
        |> World.event(:worker_set, {id, worker.cell, World.flags(worker)})

      steps ->
        move(world, id, worker, nearer(world, world.to_old_nest, worker.cell, steps))
    end
  end

  defp bring_egg(world, id, worker) do
    case Map.get(world.walk, worker.cell) do
      steps when steps != nil and steps > 1 ->
        move(world, id, worker, nearer(world, world.walk, worker.cell, steps))

      _ ->
        worker = %{worker | carry: nil, mode: :idle}

        world
        |> put(id, worker)
        |> World.event(:worker_set, {id, worker.cell, World.flags(worker)})
    end
  end

  # ---------------------------------------------------------------------------
  # Carry food to the nest

  defp carry(world, id, worker) do
    case Map.get(world.walk, worker.cell) do
      nil ->
        # There is no way to the nest. This does not occur: no step removes a locked body.
        world

      distance when distance <= 1 ->
        pile = worker.carry
        worker = %{worker | carry: nil, mode: :idle}

        world
        |> put(id, worker)
        |> World.event(:worker_set, {id, worker.cell, World.flags(worker)})
        |> World.add_nest_food(pile, 1)

      distance ->
        to = nearer(world, world.walk, worker.cell, distance)

        world
        |> move(id, worker, to)
        |> World.add_scent(to, world.p.scent_carry)
    end
  end

  # ---------------------------------------------------------------------------
  # Food

  # The nearest pile with food that the carrier can walk to: `{pile id, steps}` or nil.
  defp near_pile(world, cell) do
    Enum.reduce(world.to_pile, nil, fn {id, way}, best ->
      with steps when steps != nil <- Map.get(way, cell),
           true <- best == nil or steps < elem(best, 1),
           true <- Map.fetch!(world.piles, id).units > 0 do
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
      worker = %{worker | carry: pile, mode: :food}

      world
      |> put(id, worker)
      |> World.event(:worker_set, {id, worker.cell, World.flags(worker)})
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
  # Wait at the crossing place

  # A spare body goes as near to the crossing place as possible. One spare body waits on
  # each cell. Thus the spare bodies make a line on the bridge and a crowd behind it.
  defp wait(world, waiting, id, worker) do
    cell = worker.cell
    waiting = if worker.mode == :wait, do: waiting, else: Map.update(waiting, cell, 1, &(&1 + 1))
    worker = %{worker | mode: :wait}
    world = put(world, id, worker)

    case Map.get(world.front, cell) do
      nil ->
        # Far from the crossing place: go to the nest first. The nest is near the bridge.
        case Map.get(world.walk, cell) do
          steps when steps != nil and steps > 0 ->
            shift(world, waiting, id, worker, nearer(world, world.walk, cell, steps))

          _ ->
            {world, waiting}
        end

      steps ->
        free = fn to -> Map.get(waiting, to, 0) == 0 end
        around = Grid.neighbors(world.grid, cell)
        ahead = Enum.find(around, &(Map.get(world.front, &1) == steps - 1 and free.(&1)))
        beside = Enum.filter(around, &(Map.get(world.front, &1) == steps and free.(&1)))
        {chance, world} = random(world)

        # A free cell beside that has a free cell in front of it: the crowd spreads along
        # the crossing place.
        spread =
          Enum.filter(beside, fn to ->
            steps > 0 and
              Enum.any?(
                Grid.neighbors(world.grid, to),
                &(Map.get(world.front, &1) == steps - 1 and free.(&1))
              )
          end)

        cond do
          ahead != nil ->
            shift(world, waiting, id, worker, ahead)

          spread != [] ->
            {world, to} = pick(world, spread)
            shift(world, waiting, id, worker, to)

          # The cell has a second spare body, or the spare body moves a little: go to a
          # free cell that is not farther.
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
      |> Map.update(worker.cell, 0, &(&1 - 1))
      |> Map.update(to, 1, &(&1 + 1))

    {move(world, id, worker, to), waiting}
  end

  # ---------------------------------------------------------------------------
  # Move at random near the nest

  defp wander(world, id, worker) do
    grid = world.grid
    cell = worker.cell
    nest = world.nest
    land = Grid.land(grid, nest)
    world = put(world, id, worker)

    near? = fn to ->
      Grid.kind(grid, to) == :land and Grid.land(grid, to) == land and
        Grid.distance(grid, to, nest) <= world.p.leash
    end

    if near?.(cell) do
      {rest, world} = random(world)
      cells = Enum.filter(Grid.neighbors(grid, cell), near?)

      if rest < @rest_chance or cells == [] do
        world
      else
        {world, to} = pick(world, cells)
        move(world, id, worker, to)
      end
    else
      case Map.get(world.walk, cell) do
        nil -> world
        0 -> world
        steps -> move(world, id, worker, nearer(world, world.walk, cell, steps))
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
