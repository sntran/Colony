defmodule Colony.Workers do
  @moduledoc """
  The rules of the workers.

  A worker never locks. It follows scent, carries food, and is a spare body: after a lock,
  a player takes the body of the nearest free worker.

  A free worker is on one cell. It moves one cell at a time. The speed gives the ticks
  when a worker moves. At each move the worker uses the first rule that applies:

  1. Carry. A worker with food goes to the nest by the shortest way.
  2. Food. If the pile is near, go to it and take one unit.
  3. Bridge. On a bridge, go to the far bank. At the end of a bridge that is not
     complete, wait there if scent is near.
  4. Go out. Go to the cell with the most scent that is farther from the nest.
  5. Move at random near scent or near the nest. If the worker is too far, it goes home.
  """

  alias Colony.{Grid, World}

  # A worker that moves at random stays where it is this part of the time.
  @rest_chance 0.5
  # Each worker has a different moment in the cycle of the moves.
  @golden 0.6180339887498949

  @doc "Moves each free worker that has a move in this tick."
  def step(%World{} = world) do
    tick = world.tick
    step = world.p.step

    Enum.reduce(world.workers, world, fn {id, _}, world ->
      if moves_now?(id, tick, step) do
        # An earlier step in this tick can remove this worker. Read the worker again.
        case world.workers do
          %{^id => worker} -> decide(world, id, worker)
          _ -> world
        end
      else
        world
      end
    end)
  end

  defp moves_now?(id, tick, step) do
    phase = id * @golden
    phase = phase - Float.floor(phase)
    Float.floor(tick * step + phase) > Float.floor((tick - 1) * step + phase)
  end

  defp decide(world, id, worker) do
    cond do
      worker.carry != nil ->
        carry(world, id, worker)

      food_near?(world, worker.cell) ->
        case food(world, id, worker) do
          nil -> decide_no_food(world, id, worker)
          world -> world
        end

      true ->
        decide_no_food(world, id, worker)
    end
  end

  defp decide_no_food(world, id, worker) do
    cond do
      worker.mode == :home -> home(world, id, worker)
      at_bridge?(world, worker.cell) -> bridge(world, id, worker)
      true -> go_out(world, id, worker)
    end
  end

  # ---------------------------------------------------------------------------
  # Rule: carry

  defp carry(world, id, worker) do
    case Map.get(world.walk, worker.cell) do
      nil ->
        # There is no way to the nest. Stay near and wait for a bridge.
        wander_free(world, id, worker)

      distance when distance <= 1 ->
        world
        |> put(id, %{worker | carry: nil, crossed: nil, mode: :out})
        |> World.event(:worker_set, {id, worker.cell, 0})
        |> World.add_nest_food(worker.carry, worker.crossed)

      distance ->
        to = step_home(world, worker.cell, distance)
        # The worker keeps one locked body of its way: the record of the bridge needs it.
        crossed = if is_map_key(world.locked, to), do: to, else: worker.crossed

        world
        |> move(id, %{worker | crossed: crossed}, to)
        |> World.add_scent(to, world.p.scent_carry)
    end
  end

  # The cell that is one step nearer to the nest. With more than one, take the most scent.
  defp step_home(world, cell, distance) do
    world.grid
    |> Grid.neighbors(cell)
    |> Enum.filter(&(Map.get(world.walk, &1) == distance - 1))
    |> Enum.max_by(&World.scent(world, &1))
  end

  # ---------------------------------------------------------------------------
  # Rule: food

  # The pile is near if it is not more than some cells away and the worker has a way to
  # it on foot.
  defp food_near?(world, cell) do
    world.pile.units > 0 and is_map_key(world.to_pile, cell) and
      Grid.distance(world.grid, cell, world.pile.cell) <= world.p.food_radius
  end

  # Goes one step on the shortest way to the pile, or takes one unit.
  defp food(world, id, worker) do
    pile = world.pile
    steps = Map.fetch!(world.to_pile, worker.cell)

    if steps <= 1 do
      world
      |> put(id, %{worker | carry: pile.id, crossed: nil, mode: :out})
      |> World.event(:worker_set, {id, worker.cell, 1})
      |> World.add_scent(worker.cell, world.p.scent_carry)
      |> World.take_food()
    else
      nearer =
        Enum.filter(Grid.neighbors(world.grid, worker.cell), fn to ->
          Map.get(world.to_pile, to) == steps - 1 and World.walkable?(world, to)
        end)

      case nearer do
        [] -> nil
        list -> move(world, id, worker, Enum.max_by(list, &World.scent(world, &1)))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Rule: bridge

  # A worker is at a bridge if it is on a locked body, or on a cell of the edge of the
  # near bank that has scent and touches a locked body in the next row.
  defp at_bridge?(world, cell) do
    grid = world.grid

    case Grid.kind(grid, cell) do
      :gap ->
        true

      :near ->
        Grid.row(grid, cell) == Grid.near_edge_row(grid) and World.scent(world, cell) > 0 and
          Enum.any?(Grid.forward(grid, cell), &is_map_key(world.locked, &1))

      :far ->
        false
    end
  end

  # On a bridge, go to the far bank by the shortest way along the bodies. A worker at the
  # end of a bridge that is not complete waits there while scent is near: it is the next
  # body of a player.
  defp bridge(world, id, worker) do
    grid = world.grid
    cell = worker.cell

    next =
      case Map.get(world.to_far, cell) do
        1 -> Enum.filter(Grid.neighbors(grid, cell), &(Grid.kind(grid, &1) == :far))
        nil -> Enum.filter(Grid.forward(grid, cell), &World.walkable?(world, &1))
        steps -> Enum.filter(Grid.neighbors(grid, cell), &(Map.get(world.to_far, &1) == steps - 1))
      end

    cond do
      next != [] -> move(world, id, worker, Enum.max_by(next, &World.scent(world, &1)))
      is_map_key(world.leash, cell) -> world
      true -> home(world, id, %{worker | mode: :home})
    end
  end

  # ---------------------------------------------------------------------------
  # Rule: go out

  defp go_out(world, id, worker) do
    grid = world.grid
    cell = worker.cell
    distance = Grid.nest_distance(grid, cell)

    with_scent =
      for to <- Grid.neighbors(grid, cell),
          scent = World.scent(world, to),
          scent > 0,
          Grid.nest_distance(grid, to) > distance,
          World.walkable?(world, to),
          do: {scent, to}

    case with_scent do
      [] ->
        if is_map_key(world.leash, cell) do
          wander(world, id, worker)
        else
          home(world, id, %{worker | mode: :home})
        end

      list ->
        {best, _} = Enum.max(list)
        {world, to} = pick(world, for({^best, to} <- list, do: to))
        move(world, id, worker, to)
    end
  end

  # Moves at random, but stays near scent or near the nest, and on the bank.
  defp wander(world, id, worker) do
    {rest, world} = random(world)

    if rest < @rest_chance do
      world
    else
      cells =
        Enum.filter(Grid.neighbors(world.grid, worker.cell), fn to ->
          is_map_key(world.leash, to) and World.walkable?(world, to)
        end)

      case cells do
        [] ->
          world

        cells ->
          {world, to} = pick(world, cells)
          move(world, id, worker, to)
      end
    end
  end

  # Moves at random on the cells where a body can be. For a worker that has no way home.
  defp wander_free(world, id, worker) do
    {rest, world} = random(world)

    if rest < @rest_chance do
      world
    else
      case Enum.filter(Grid.neighbors(world.grid, worker.cell), &World.walkable?(world, &1)) do
        [] ->
          world

        cells ->
          {world, to} = pick(world, cells)
          move(world, id, worker, to)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Rule: go home

  defp home(world, id, worker) do
    grid = world.grid
    cell = worker.cell

    cond do
      Grid.kind(grid, cell) == :near and is_map_key(world.leash, cell) ->
        go_out(put(world, id, %{worker | mode: :out}), id, %{worker | mode: :out})

      true ->
        case Map.get(world.walk, cell) do
          nil ->
            wander_free(put(world, id, worker), id, worker)

          0 ->
            put(world, id, %{worker | mode: :out})

          distance ->
            move(world, id, worker, step_home(world, cell, distance))
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
