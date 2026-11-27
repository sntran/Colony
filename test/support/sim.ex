defmodule Colony.Sim do
  @moduledoc """
  Helpers for the tests. They play the game through the same functions that the server uses.
  """

  alias Colony.{Grid, World}

  @doc "The game config with changes for a test: no workers and no helpers, and seed 1."
  def cfg(changes \\ []) do
    :colony
    |> Application.fetch_env!(:game)
    |> Keyword.merge(seed: 1, workers: 0, helpers: 0)
    |> Keyword.merge(changes)
  end

  @doc "A config with one river that has the same width in all its columns."
  def straight(rows, changes \\ []), do: cfg(Keyword.merge([rivers: [{rows, rows}]], changes))

  @doc "Moves the world `count` ticks. The events are not kept."
  def run(world, count) do
    Enum.reduce(1..count//1, world, fn _, world -> elem(World.tick(world), 0) end)
  end

  @doc "Moves the world until `done?` is true or `limit` ticks go by. Returns `{world, ticks}` or `{world, nil}`."
  def run_until(world, limit, done?) do
    Enum.reduce_while(1..limit//1, {world, nil}, fn n, {world, _} ->
      {world, _events} = World.tick(world)
      if done?.(world), do: {:halt, {world, n}}, else: {:cont, {world, nil}}
    end)
  end

  @doc "Waits until the body of the player can lock."
  def wait_ready(world, id) do
    ready? = fn world -> world.tick >= world.players[id].ready_tick end

    if ready?.(world) do
      world
    else
      {world, ticks} = run_until(world, 200, ready?)
      true = ticks != nil
      world
    end
  end

  @doc """
  Walks the body of a player to a cell, as a client does: small steps along the cells
  where a body can be, with one tick between the steps.
  """
  def walk(world, id, target) do
    world = wait_ready(world, id)
    path = path(world, world.players[id].cell, target)
    if path == nil, do: raise("no way to cell #{target}")

    Enum.reduce(path, world, fn cell, world ->
      {x, z} = Grid.center(world.grid, cell)
      step_to(world, id, x, z)
    end)
  end

  defp step_to(world, id, x, z) do
    player = world.players[id]
    dx = x - player.x
    dz = z - player.z
    distance = :math.sqrt(dx * dx + dz * dz)

    if distance < 0.001 do
      world
    else
      part = min(1.0, world.p.step / distance)
      world = World.move(world, id, player.x + dx * part, player.z + dz * part, 0.0)
      {world, _} = World.tick(world)
      # The world must accept each step.
      true = abs(world.players[id].x - (player.x + dx * part)) < 0.01
      step_to(world, id, x, z)
    end
  end

  @doc "Walks to a cell that touches `cell`, then locks into `cell`. Returns `{result, world}`."
  def walk_and_lock(world, id, cell) do
    world = wait_ready(world, id)
    from = world.players[id].cell

    stand =
      world.grid
      |> Grid.neighbors(cell)
      |> Enum.filter(&(World.walkable?(world, &1) and path(world, from, &1) != nil))
      |> Enum.min_by(&length(path(world, from, &1)))

    world = walk(world, id, stand)
    World.lock(world, id, cell)
  end

  @doc "Same as `walk_and_lock/3`, but the lock must be possible."
  def lock!(world, id, cell) do
    {:ok, world} = walk_and_lock(world, id, cell)
    world
  end

  @doc """
  The player locks into open cells until the bridge of the river `k` is complete.
  `pick` takes one cell from the sorted list of the open cells.
  """
  def cross!(world, id, k, pick \\ &hd/1) do
    if world.stage > k do
      world
    else
      ^k = world.stage
      cell = world.open |> Enum.sort() |> pick.()
      cross!(lock!(world, id, cell), id, k, pick)
    end
  end

  @doc "The shortest way on foot from a cell to a cell, without the first cell. Nil if there is no way."
  def path(_world, from, from), do: []

  def path(world, from, to) do
    search(world, [from], %{from => nil}, to)
  end

  defp search(_world, [], _seen, _to), do: nil

  defp search(world, front, seen, to) do
    {next, seen} =
      Enum.reduce(front, {[], seen}, fn cell, acc ->
        Enum.reduce(Grid.neighbors(world.grid, cell), acc, fn n, {next, seen} = acc ->
          if is_map_key(seen, n) or not World.walkable?(world, n) do
            acc
          else
            {[n | next], Map.put(seen, n, cell)}
          end
        end)
      end)

    if is_map_key(seen, to), do: trace(seen, to, []), else: search(world, next, seen, to)
  end

  defp trace(seen, cell, path) do
    case Map.fetch!(seen, cell) do
      nil -> path
      before -> trace(seen, before, [cell | path])
    end
  end

  @doc "The cell of river `k` in row `n` (1 is the row at the south edge) and in a column."
  def river_cell(world, k \\ 1, n, col) do
    Grid.cell(world.grid, Grid.river_start(world.grid, k) + n - 1, col)
  end

  @doc "The cells that a free body can get to on foot from a cell."
  def reach(world, from) do
    World.flood(world.grid, [from], %{from => 0}, 1, :infinity, &World.walkable?(world, &1))
  end

  @doc "True if a free body can go on foot from the nest to the pile `k`."
  def way_to_pile?(world, k), do: is_map_key(world.walk, world.piles[k].cell)
end
