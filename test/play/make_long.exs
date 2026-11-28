# Makes a save file of a world with many crossings, fast: 6 players lock into the open
# cells with the most gain, with no walk. The rules of the lock are the rules of the game.
# The screenshots of lands 5 to 8 and of a story of 10 rivers use this world.
#
#     mix run --no-start test/play/make_long.exs RIVERS PATH [SEED]
#
# For the screenshots: mix run --no-start test/play/make_long.exs 10 tmp/long10.bin 7

alias Colony.{Grid, Store, World}

[rivers, path | rest] = System.argv()
rivers = String.to_integer(rivers)
seed = String.to_integer(List.first(rest) || "7")
cfg = Keyword.merge(Application.fetch_env!(:colony, :game), seed: seed, helpers: 0)

names = [
  "Brisk Fern 12",
  "Steady Berry 18",
  "Quiet Moss 7",
  "Eager Thorn 74",
  "Dusty Pine 45",
  "Bold Reed 3"
]

{world, ids} =
  Enum.reduce(names, {World.new(cfg), []}, fn name, {world, ids} ->
    secret = String.duplicate(String.replace(name, " ", ""), 3)
    {world, id} = World.join(world, name, secret)
    {world, ids ++ [id]}
  end)

world = %{world | start: 1_790_000_000, now: 1_790_000_000}

place = fn world, id, cell ->
  stand = world.grid |> Grid.neighbors(cell) |> Enum.find(&World.walkable?(world, &1))
  {x, z} = Grid.center(world.grid, stand)
  player = %{world.players[id] | x: x, z: z, cell: stand, ready_tick: 0, carry: nil}
  world = World.put_player(world, id, player)
  pile = max(1, world.stage - 1)

  world =
    if World.spare(world) == 0,
      do: World.add_nest_food(world, pile, 5, world.players[id]),
      else: world

  # Each lock is 3 seconds after the lock before it.
  {:ok, world} = World.lock(%{world | now: world.now + 3}, id, cell)
  elem(World.take_events(world), 0)
end

{world, _} =
  Enum.reduce(1..rivers, {world, 0}, fn k, {world, n} ->
    Stream.iterate({world, n}, fn {world, n} ->
      id = Enum.at(ids, rem(div(n, 3), length(ids)))
      cell = world.open |> Enum.max_by(fn {cell, gain} -> {gain, -cell} end) |> elem(0)
      {place.(world, id, cell), n + 1}
    end)
    |> Enum.find(fn {world, _} -> world.stage > k end)
  end)

world = Enum.reduce(ids, world, &World.leave(&2, &1))
:ok = Store.save(path, World.to_save(world))

IO.puts(
  "#{path}: #{world.stage - 1} crossings, #{map_size(world.locked)} locked bodies, " <>
    "#{World.rivers(world)} rivers, #{world.grid.rows} rows"
)
