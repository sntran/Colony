defmodule Colony.Helpers do
  @moduledoc """
  The rules of the helpers.

  A helper is a body that the server controls with the rules of a player: the same speed,
  the same lock rule, and at a lock it takes the body of a spare body. A helper obeys the
  guide (`Colony.Guide`), as a person does with the page:

  - The guide shows an open cell: the helper goes to it and locks. All the helpers
    together lock one time each `helper_lock_seconds / n` seconds, with `n` helpers, and
    they lock in turn. Thus a bridge grows at a constant speed that a person can see.
  - The guide shows a pile: the helper goes to it and takes food.
  - The guide shows the nest: the helper brings the food to the nest.
  - No target: the helper waits.
  """

  alias Colony.{Grid, Guide, World}

  # A helper asks the guide again after this many ticks.
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
    # The goal changes at once when the body gets or loses food.
    changed? = player.carry != nil != (helper.goal == :nest)

    if look? or changed? or helper.goal == nil do
      plan(world, id, player)
    else
      go(world, id, player)
    end
  end

  # Asks the guide for the target, then goes one tick to it.
  defp plan(world, id, %{helper: helper} = player) do
    helper =
      case Guide.target(world, player) do
        {:open, cell, _stand, path} -> %{helper | goal: :open, target: cell, path: path}
        {:pile, pile, _cell} -> %{helper | goal: :pile, target: pile, path: []}
        {:nest, cell} -> %{helper | goal: :nest, target: cell, path: []}
        nil -> %{helper | goal: :wait, target: nil, path: []}
      end

    go(world, id, %{player | helper: helper})
  end

  defp go(world, id, %{helper: helper} = player) do
    case helper.goal do
      :open ->
        cond do
          not World.open?(world, helper.target) -> put(world, id, player, %{helper | goal: nil})
          helper.path != [] -> walk(world, id, player)
          true -> try_lock(world, id, player)
        end

      :pile ->
        case Map.get(world.to_pile, helper.target) do
          nil -> put(world, id, player, %{helper | goal: nil})
          way -> along(world, id, player, helper, way)
        end

      :nest ->
        along(world, id, player, helper, world.walk)

      _ ->
        put(world, id, player, helper)
    end
  end

  defp put(world, id, player, helper) do
    World.put_player(world, id, %{player | helper: helper})
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

          if next, do: [next], else: [player.cell]

        path ->
          path
      end

    walk(world, id, %{player | helper: %{helper | path: path}})
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
        case World.lock(world, id, target) do
          {:ok, world} ->
            player = Map.fetch!(world.players, id)
            count = Enum.count(world.players, fn {_id, other} -> other.helper != nil end)
            ticks = div(world.p.helper_lock_ticks, count)
            world = %{world | helper_tick: world.tick + ticks}
            # The helper lets each other helper lock before its next lock.
            next_lock = world.tick + ticks * count - div(ticks, 2)

            put(world, id, player, %{
              helper
              | goal: nil,
                target: nil,
                path: [],
                next_lock: next_lock
            })

          {_error, world} ->
            put(world, id, player, %{helper | goal: nil, target: nil, path: []})
        end
    end
  end
end
