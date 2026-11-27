defmodule Colony.Helpers do
  @moduledoc """
  The rules of the helpers.

  A helper is a body that the server controls with the rules of a player: the same speed,
  the same lock rule, and at a lock it takes the body of a worker.

  1. A helper with food goes to the nest.
  2. If the colony has a spare body and an open cell, the helper goes to the nearest open
     cell and locks. All the helpers together lock one time each `helper_lock_seconds / n`
     seconds, with `n` helpers, and they lock in turn. Thus a bridge grows at a constant
     speed that a person can see.
  3. If not, the helper goes to the nearest pile with food and carries food to the nest,
     as a player does.
  """

  alias Colony.{Grid, World}

  # A helper looks for work again after this many ticks.
  @look_ticks 10

  @doc "The state of the rules of helper number `n`."
  def new(n), do: %{n: n, goal: nil, target: nil, path: [], next_lock: 0}

  @doc "Moves each helper one tick."
  def step(%World{} = world) do
    Enum.reduce(world.players, world, fn
      {id, %{helper: %{}}}, world -> act(world, id, Map.fetch!(world.players, id))
      _, world -> world
    end)
  end

  defp act(world, id, %{helper: helper} = player) do
    look? = rem(world.tick + helper.n, @look_ticks) == 0

    cond do
      player.carry != nil ->
        along(world, id, player, %{helper | goal: :nest, target: nil}, world.walk)

      helper.goal == :lock ->
        cond do
          not World.open?(world, helper.target) or World.spare(world) == 0 ->
            put(world, id, player, %{helper | goal: nil, target: nil, path: []})

          helper.path != [] ->
            walk(world, id, player)

          true ->
            try_lock(world, id, player)
        end

      look? or helper.goal == nil ->
        plan(world, id, player)

      helper.goal == :food ->
        go_to_food(world, id, player)

      true ->
        world
    end
  end

  defp put(world, id, player, helper) do
    World.put_player(world, id, %{player | helper: helper})
  end

  # ---------------------------------------------------------------------------
  # The plan

  defp plan(world, id, %{helper: helper} = player) do
    place = if World.spare(world) > 0, do: place_to_lock(world, player.cell)

    cond do
      place != nil ->
        {target, path} = place
        put(world, id, player, %{helper | goal: :lock, target: target, path: path})

      near_pile(world, player.cell) != nil ->
        go_to_food(world, id, %{player | helper: %{helper | goal: :food, target: nil, path: []}})

      true ->
        put(world, id, player, %{helper | goal: :idle, target: nil, path: []})
    end
  end

  # The nearest open cell: `{open cell, the way to a cell that touches it}`, or nil.
  defp place_to_lock(world, from) do
    if MapSet.size(world.open) == 0, do: nil, else: search(world, [from], %{from => nil})
  end

  defp search(_world, [], _before), do: nil

  defp search(world, front, before) do
    grid = world.grid

    found =
      Enum.find_value(Enum.sort(front), fn cell ->
        case Enum.find(Grid.neighbors(grid, cell), &World.open?(world, &1)) do
          nil -> nil
          open -> {open, trace(before, cell, [])}
        end
      end)

    if found do
      found
    else
      {next, before} =
        Enum.reduce(front, {[], before}, fn cell, acc ->
          Enum.reduce(Grid.neighbors(grid, cell), acc, fn to, {next, before} = acc ->
            if is_map_key(before, to) or not World.walkable?(world, to) do
              acc
            else
              {[to | next], Map.put(before, to, cell)}
            end
          end)
        end)

      search(world, next, before)
    end
  end

  defp trace(before, cell, path) do
    case Map.fetch!(before, cell) do
      nil -> path
      previous -> trace(before, previous, [cell | path])
    end
  end

  # The nearest pile with food that the helper can walk to.
  defp near_pile(world, cell) do
    world.piles
    |> Enum.filter(fn {id, pile} ->
      pile.units > 0 and is_map_key(Map.fetch!(world.to_pile, id), cell)
    end)
    |> Enum.min_by(fn {id, _pile} -> Map.fetch!(Map.fetch!(world.to_pile, id), cell) end, fn ->
      nil
    end)
  end

  defp go_to_food(world, id, %{helper: helper} = player) do
    case near_pile(world, player.cell) do
      nil -> put(world, id, player, %{helper | goal: nil})
      {pile, _} -> along(world, id, player, helper, Map.fetch!(world.to_pile, pile))
    end
  end

  # ---------------------------------------------------------------------------
  # Walk and lock

  # Goes one tick along a map of steps, to the cell with the number 0.
  defp along(world, id, player, helper, way) do
    path =
      case helper.path do
        [] ->
          steps = Map.get(way, player.cell)

          next =
            steps && steps > 0 &&
              Enum.find(Grid.neighbors(world.grid, player.cell), &(Map.get(way, &1) == steps - 1))

          if next, do: [next], else: []

        path ->
          path
      end

    if path == [],
      do: put(world, id, player, helper),
      else: walk(world, id, %{player | helper: %{helper | path: path}})
  end

  # Goes along the cells of the way, at the speed of a player.
  defp walk(world, id, %{helper: helper} = player) do
    [next | rest] = helper.path

    if World.walkable?(world, next) do
      {x, z} = Grid.center(world.grid, next)
      dx = x - player.x
      dz = z - player.z
      distance = :math.sqrt(dx * dx + dz * dz)
      step = world.p.step

      {x, z, path} =
        if distance <= step,
          do: {x, z, rest},
          else: {player.x + dx / distance * step, player.z + dz / distance * step, helper.path}

      cell = Grid.cell_at(world.grid, x, z)
      world = if cell != player.cell, do: World.cross(world, cell), else: world
      heading = if distance > 0.001, do: :math.atan2(dx, dz), else: player.heading
      player = %{player | x: x, z: z, cell: cell, heading: heading}
      put(world, id, player, %{helper | path: path})
    else
      put(world, id, player, %{helper | goal: nil, target: nil, path: []})
    end
  end

  # The helper is at a cell that touches the open cell. It locks when the rules permit it.
  defp try_lock(world, id, %{helper: helper} = player) do
    target = helper.target

    cond do
      target not in Grid.neighbors(world.grid, player.cell) ->
        put(world, id, player, %{helper | goal: nil, target: nil, path: []})

      world.tick < player.ready_tick or world.tick < world.helper_tick or
          world.tick < helper.next_lock ->
        # Look in the direction of the cell while the helper waits.
        {x, z} = Grid.center(world.grid, target)
        heading = :math.atan2(x - player.x, z - player.z)
        put(world, id, %{player | heading: heading}, helper)

      true ->
        {:ok, world} = World.lock(world, id, target)
        player = Map.fetch!(world.players, id)
        count = Enum.count(world.players, fn {_id, other} -> other.helper != nil end)
        ticks = div(world.p.helper_lock_ticks, count)
        world = %{world | helper_tick: world.tick + ticks}
        # The helper lets each other helper lock before its next lock.
        next_lock = world.tick + ticks * count - div(ticks, 2)
        put(world, id, player, %{helper | goal: nil, target: nil, path: [], next_lock: next_lock})
    end
  end
end
