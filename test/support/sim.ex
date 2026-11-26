defmodule Colony.Sim do
  @moduledoc """
  Helpers for the tests. They play the game through the same functions that the server uses.
  """

  alias Colony.{Grid, World}

  @doc "The game config with changes for a test."
  def cfg(changes \\ []) do
    :colony
    |> Application.fetch_env!(:game)
    |> Keyword.merge(seed: 1, workers: 0)
    |> Keyword.merge(changes)
  end

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

  @doc "Waits until the player has a body."
  def wait_alive(world, id) do
    {world, _} = run_until(world, 100, &(&1.players[id].state == :alive))
    world
  end

  @doc """
  Walks the body of a player to a cell, as a client does: small steps along the cells
  where a body can be, with one tick between the steps.
  """
  def walk(world, id, target) do
    world = wait_alive(world, id)
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
      world = World.move(world, id, player.x + dx * part, player.z + dz * part, 0.0, false)
      {world, _} = World.tick(world)
      # The world must accept each step.
      true = abs(world.players[id].x - (player.x + dx * part)) < 0.01
      step_to(world, id, x, z)
    end
  end

  @doc "Walks to a cell that touches `cell`, then locks into `cell`. Returns `{result, world}`."
  def walk_and_lock(world, id, cell) do
    world = wait_alive(world, id)

    stand =
      world.grid
      |> Grid.neighbors(cell)
      |> Enum.filter(&World.walkable?(world, &1))
      |> Enum.min_by(&Grid.row(world.grid, &1))

    world = walk(world, id, stand)
    World.lock(world, id, cell)
  end

  @doc "Same as `walk_and_lock/3`, but the lock must be possible."
  def lock!(world, id, cell) do
    {:ok, world} = walk_and_lock(world, id, cell)
    world
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

  @doc "The cell of the gap in row `n` (1 is the row at the near bank) and in a column."
  def gap_cell(world, n, col) do
    Grid.cell(world.grid, world.grid.near_rows + n - 1, col)
  end

  @doc "The locked workers."
  def locked_workers(world) do
    for {cell, %{kind: :worker}} <- world.locked, do: cell
  end
end
