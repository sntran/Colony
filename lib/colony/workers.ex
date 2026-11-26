defmodule Colony.Workers do
  @moduledoc """
  The rules of the workers.

  A free worker is on one cell. It moves one cell at a time. The speed gives the ticks
  when a worker moves. At each move the worker uses the first rule that applies:

  1. Carry. A worker with food goes to the nest by the shortest way.
  2. Food. If food is near, go to it and take one unit.
  3. Bridge. At the gap with scent, or on a bridge: go to the far bank, or lock.
  4. Go out. Go to the cell with the most scent that is farther from the nest.
  5. Move at random near scent or near the nest. If the worker is too far, it goes home.
  """

  alias Colony.{Grid, Support, World}

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
        # An earlier worker in this tick can change this worker. Read the worker again.
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
    cell = worker.cell
    world = World.touch(world, cell)

    cond do
      worker.carry ->
        carry(world, id, worker)

      food_near?(world, cell) ->
        case food(world, id, worker) do
          nil -> decide_no_food(world, id, worker)
          world -> world
        end

      true ->
        decide_no_food(world, id, worker)
    end
  end

  defp decide_no_food(world, id, worker) do
    cell = worker.cell

    cond do
      worker.mode == :home -> home(world, id, worker)
      at_bridge?(world, cell) -> bridge(world, id, worker)
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
        |> put(id, %{worker | carry: false, mode: :out})
        |> World.event(:worker_set, {id, worker.cell, 0})
        |> World.add_nest_food()

      distance ->
        to = step_home(world, worker.cell, distance)

        world
        |> move(id, worker, to)
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

  defp food_near?(world, cell) do
    world.food_pile > 0 and Grid.food_distance(world.grid, cell) <= world.p.food_radius
  end

  # Returns nil if the worker cannot go nearer to the food from this cell.
  defp food(world, id, worker) do
    grid = world.grid
    distance = Grid.food_distance(grid, worker.cell)

    if distance <= 1 do
      world
      |> put(id, %{worker | carry: true, mode: :out})
      |> World.event(:worker_set, {id, worker.cell, 1})
      |> World.take_food()
      |> World.add_scent(worker.cell, world.p.scent_carry)
    else
      nearer =
        Enum.filter(Grid.neighbors(grid, worker.cell), fn to ->
          Grid.food_distance(grid, to) < distance and World.walkable?(world, to)
        end)

      case nearer do
        [] -> nil
        list -> move(world, id, worker, Enum.max_by(list, &World.scent(world, &1)))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Rule: bridge

  # A worker is at a bridge if it is on a locked body, or on the edge of the near bank
  # on a cell that has scent.
  defp at_bridge?(world, cell) do
    grid = world.grid

    case Grid.kind(grid, cell) do
      :gap -> true
      :near -> Grid.row(grid, cell) == Grid.near_edge_row(grid) and World.scent(world, cell) > 0
      :far -> false
    end
  end

  defp bridge(world, id, worker) do
    cell = worker.cell

    case look_ahead(world, cell) do
      {:complete, _} ->
        move(world, id, worker, forward_step(world, cell))

      {:end, last} ->
        target = extension(world, last)

        cond do
          target != nil and last == cell ->
            lock(world, id, target)

          target != nil ->
            move(world, id, worker, next_body(world, cell))

          beside = beside_target(world, cell) ->
            lock(world, id, beside)

          last != cell ->
            move(world, id, worker, next_body(world, cell))

          true ->
            # The bridge cannot grow from here. Go home.
            home(world, id, %{worker | mode: :home})
        end
    end
  end

  # Follows the bridge from a cell in the direction of the far bank.
  # Returns `{:complete, cell}` if the way gets to the far bank, or `{:end, cell}` with
  # the last cell of the way.
  defp look_ahead(world, cell) do
    forward = Grid.forward(world.grid, cell)

    cond do
      Enum.any?(forward, &(Grid.kind(world.grid, &1) == :far)) -> {:complete, cell}
      next = Enum.find(forward, &is_map_key(world.locked, &1)) -> look_ahead(world, next)
      true -> {:end, cell}
    end
  end

  defp next_body(world, cell) do
    Enum.find(Grid.forward(world.grid, cell), &is_map_key(world.locked, &1))
  end

  # On a complete bridge, take the cell in the next row that has the most scent.
  defp forward_step(world, cell) do
    world.grid
    |> Grid.forward(cell)
    |> Enum.filter(&World.walkable?(world, &1))
    |> Enum.max_by(&World.scent(world, &1))
  end

  # The cell in the next row where a body can lock, or nil.
  # A cell beside a locked body is better: the two bodies then have a lower cost.
  defp extension(world, last) do
    cells = Enum.filter(Grid.forward(world.grid, last), &World.can_lock?(world, &1))

    Enum.find(cells, &(not Support.alone?(world.grid, world.locked, &1))) || List.first(cells)
  end

  # The cell beside a body that is alone in its row, or nil.
  defp beside_target(world, cell) do
    grid = world.grid

    if is_map_key(world.locked, cell) and Support.alone?(grid, world.locked, cell) do
      case Enum.filter(Grid.beside(grid, cell), &World.can_lock?(world, &1)) do
        [] ->
          nil

        cells ->
          # Take the side that touches more locked bodies. The bridge then stays straight.
          Enum.max_by(cells, fn to ->
            Enum.count(Grid.neighbors(grid, to), &is_map_key(world.locked, &1))
          end)
      end
    end
  end

  defp lock(world, id, target) do
    body = %{kind: :worker, id: id, name: "", time: world.now}

    %{world | workers: Map.delete(world.workers, id)}
    |> World.event(:worker_gone, id)
    |> World.put_lock(target, body)
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

  # Moves at random, but stays near scent or near the nest.
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
    |> World.touch(to)
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
