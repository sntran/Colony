defmodule Colony.Helpers do
  @moduledoc """
  The rules of the helpers.

  A helper is a body that the server controls with the rules of a player: the same speed,
  the same lock rule, and after a lock it takes the body of a worker. A helper locks one
  time each some seconds at most. The helpers lock in turn, with the same time between
  two locks, thus a bridge grows at a constant speed that a person can see.

  A helper builds to the pile:

  1. It continues the bridge that is nearest to the pile and not complete. If the cell of
     the near bank that is nearest to the pile is nearer, it starts a bridge there.
  2. It locks in the next row of the bridge, in the cell that is nearest to the pile.
  3. If no lock is possible in the next row, it locks beside the body that gives the
     longest reach.
  4. When a complete bridge is near the pile, the helper goes one time from the nest to
     the pile, as a player does to show the way to the workers. Then it has no work.

  A helper puts scent while it has work. Thus the workers come to the bridge, and they are
  the next bodies.
  """

  alias Colony.{Grid, Support, World}

  # A helper with no work, or with work that is not possible now, looks again after this
  # many ticks.
  @look_ticks 10

  @doc "Moves each helper one tick."
  def step(%World{} = world) do
    Enum.reduce(world.players, world, fn
      {id, %{helper: %{}, state: :alive}}, world -> act(world, id, Map.fetch!(world.players, id))
      _, world -> world
    end)
  end

  defp act(world, id, %{helper: helper} = player) do
    cond do
      helper.plan == nil ->
        if rem(world.tick + helper.n, @look_ticks) == 0 do
          plan = plan(world, player)
          put(world, id, player, %{helper | plan: plan, path: (plan && plan.path) || []})
        else
          put(world, id, %{player | scent: false}, helper)
        end

      helper.path != [] ->
        walk(world, id, player)

      helper.plan.target == nil ->
        # The end of the way to the pile.
        put(world, id, player, %{helper | plan: nil, shown: world.pile.id})

      true ->
        try_lock(world, id, player)
    end
  end

  defp put(world, id, player, helper) do
    World.put_player(world, id, %{player | helper: helper, scent: helper.plan != nil})
  end

  # ---------------------------------------------------------------------------
  # Walk and lock

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
      put(world, id, player, %{helper | plan: nil, path: []})
    end
  end

  # The helper is at the cell of its plan. It locks when the rules permit it.
  defp try_lock(world, id, %{helper: helper} = player) do
    target = helper.plan.target

    cond do
      not World.can_lock?(world, target) or target not in Grid.neighbors(world.grid, player.cell) ->
        put(world, id, player, %{helper | plan: nil, path: []})

      world.tick < helper.next_lock or world.tick < player.ready_tick or
          world.tick < world.helper_tick ->
        # Look in the direction of the cell while the helper waits.
        {x, z} = Grid.center(world.grid, target)
        heading = :math.atan2(x - player.x, z - player.z)
        put(world, id, %{player | heading: heading}, helper)

      true ->
        {:ok, world} = World.lock(world, id, target)
        player = Map.fetch!(world.players, id)
        ticks = world.p.helper_lock_ticks
        count = Enum.count(world.players, fn {_id, other} -> other.helper != nil end)
        world = %{world | helper_tick: world.tick + div(ticks, count)}
        put(world, id, player, %{helper | plan: nil, path: [], next_lock: world.tick + ticks})
    end
  end

  # ---------------------------------------------------------------------------
  # The plan: the cell for the next lock, and the way to a cell that touches it

  defp plan(world, player) do
    grid = world.grid
    pile = world.pile
    groups = World.bridges(world)

    if work_done?(world, groups) do
      if player.helper.shown == world.pile.id, do: nil, else: show_way(world, player)
    else
      # The cells that the helper can get to on foot, with the cell before each one.
      {steps, before} = ways(world, player.cell)
      far = &Grid.distance(grid, &1, pile.cell)

      open =
        Enum.filter(groups, fn group ->
          not World.complete?(world, group) and Enum.any?(group, &is_map_key(steps, &1))
        end)

      bridge =
        Enum.min_by(open, fn group -> group |> Enum.map(far) |> Enum.min() end, fn -> nil end)

      start = start_cell(world, steps, far)

      target =
        cond do
          bridge == nil -> start
          start == nil -> next_cell(world, bridge, far)
          far.(start) < bridge |> Enum.map(far) |> Enum.min() -> start
          true -> next_cell(world, bridge, far)
        end

      target && make_plan(world, target, steps, before)
    end
  end

  # The way from the cell of the helper to the nest, and from the nest to the pile.
  # The helper puts scent on all of it.
  defp show_way(world, player) do
    grid = world.grid
    {_steps, to_nest} = ways(world, grid.nest)
    {steps, from_nest} = ways(world, grid.nest)
    near_pile = Enum.filter(Grid.neighbors(grid, world.pile.cell), &is_map_key(steps, &1))

    if is_map_key(to_nest, player.cell) and near_pile != [] do
      # `to_nest` has the cell before each cell on the way from the nest. The way of the
      # helper to the nest is the same cells in the opposite order.
      home = trace(to_nest, player.cell, []) |> Enum.reverse() |> Enum.drop(1)
      out = trace(from_nest, Enum.min_by(near_pile, &Map.fetch!(steps, &1)), [])
      %{target: nil, path: (home ++ [grid.nest | out]) |> Enum.dedup()}
    end
  end

  # A complete bridge that is near the pile: the helpers build no more.
  defp work_done?(world, groups) do
    Enum.any?(groups, fn group ->
      World.complete?(world, group) and
        Enum.any?(group, fn cell ->
          abs(Grid.col(world.grid, cell) - world.pile.col) < world.p.pile_bridge_columns
        end)
    end)
  end

  # The first cell of a new bridge: the river cell at the near bank that is nearest to the pile.
  defp start_cell(world, steps, far) do
    grid = world.grid
    row = Grid.near_edge_row(grid)

    cells =
      for col <- 0..(grid.width - 1),
          edge = Grid.cell(grid, row, col),
          is_map_key(steps, edge),
          cell <- Grid.forward(grid, edge),
          World.can_lock?(world, cell),
          do: cell

    Enum.min_by(cells, far, fn -> nil end)
  end

  # The next cell of a bridge: in the next row if a lock is possible there. If not, beside
  # the body that gives the longest reach.
  defp next_cell(world, bridge, far) do
    grid = world.grid
    top = bridge |> Enum.map(&Grid.row(grid, &1)) |> Enum.max()

    ahead =
      for cell <- bridge,
          Grid.row(grid, cell) == top,
          next <- Grid.forward(grid, cell),
          World.can_lock?(world, next),
          uniq: true,
          do: next

    case ahead do
      [] ->
        beside =
          for cell <- bridge,
              next <- Grid.beside(grid, cell),
              World.can_lock?(world, next),
              uniq: true,
              do: next

        Enum.max_by(beside, &{reach_with(world, &1), -far.(&1)}, fn -> nil end)

      cells ->
        Enum.min_by(cells, far)
    end
  end

  # The reach of the bridge if a body locks into the cell: `{bank?, row}`.
  defp reach_with(world, cell) do
    supports = Support.with_body(world.grid, world.rule, world.locked, cell)
    locked = Map.put(world.locked, cell, true)
    {row, bank?} = Support.reach(world.grid, world.rule, locked, supports)
    {bank?, row}
  end

  defp make_plan(world, target, steps, before) do
    stand =
      world.grid
      |> Grid.neighbors(target)
      |> Enum.filter(&is_map_key(steps, &1))
      |> Enum.min_by(&Map.fetch!(steps, &1), fn -> nil end)

    stand && %{target: target, path: trace(before, stand, [])}
  end

  defp trace(before, cell, path) do
    case Map.fetch!(before, cell) do
      nil -> path
      previous -> trace(before, previous, [cell | path])
    end
  end

  # The number of steps on foot from a cell to each cell, and the cell before each cell.
  defp ways(world, from), do: ways(world, [from], %{from => 0}, %{from => nil}, 1)

  defp ways(_world, [], steps, before, _distance), do: {steps, before}

  defp ways(world, front, steps, before, distance) do
    {next, steps, before} =
      Enum.reduce(front, {[], steps, before}, fn cell, acc ->
        Enum.reduce(Grid.neighbors(world.grid, cell), acc, fn to, {next, steps, before} = acc ->
          if is_map_key(steps, to) or not World.walkable?(world, to) do
            acc
          else
            {[to | next], Map.put(steps, to, distance), Map.put(before, to, cell)}
          end
        end)
      end)

    ways(world, next, steps, before, distance + 1)
  end
end
