defmodule Colony.BodiesTest do
  @moduledoc "Plan 0002, section 4.3: after a lock, the player takes the body of a worker."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  @col 30

  defp edge(world), do: Grid.cell(world.grid, 13, @col)

  test "after a lock, the player has the body of the nearest free worker" do
    {world, id} = World.join(World.new(Sim.straight(8, workers: 6)), "Ada")
    world = Sim.walk(world, id, edge(world))
    count = map_size(world.workers)

    # One worker is 2 steps from the cell of the lock. The others are near the nest.
    near = Grid.cell(world.grid, 12, @col)
    world = %{world | workers: Map.put(world.workers, 0, %{world.workers[0] | cell: near})}

    target = Sim.river_cell(world, 1, @col)
    assert {:ok, world} = World.lock(world, id, target)

    # The player has the new body immediately, and it is the body of that worker.
    player = world.players[id]
    assert player.state == :alive
    assert player.cell == near
    assert player.took == 0
    assert {player.x, player.z} == Grid.center(world.grid, near)

    # That worker is not a worker after that.
    refute is_map_key(world.workers, 0)
    assert map_size(world.workers) == count - 1

    # In the next tick, the clients get the lock and the worker that is gone.
    {world, events} = World.tick(world)
    assert events.worker_gone == [0]
    assert [{^target, %{name: "Ada", helper: false}, ^id}] = events.locks
    assert world.players[id].state == :alive
  end

  test "a body that a player took cannot lock for 1 second" do
    {world, id} = World.join(World.new(Sim.straight(8, workers: 6)), "Ada")
    world = Sim.walk(world, id, edge(world))
    world = %{world | workers: Map.put(world.workers, 0, %{world.workers[0] | cell: edge(world)})}
    assert {:ok, world} = World.lock(world, id, Sim.river_cell(world, 1, @col))
    assert world.players[id].cell == edge(world)

    # The new body is at the river, and a lock is possible in the next cell. But not now.
    other = Sim.river_cell(world, 1, @col + 1)
    assert World.can_lock?(world, other)
    assert {{:error, _}, _} = World.lock(world, id, other)
    assert {{:error, _}, _} = world |> Sim.run(9) |> World.lock(id, other)
    assert {:ok, _} = world |> Sim.run(10) |> World.lock(id, other)
  end

  test "a worker that carries food is not used" do
    {world, id} = World.join(World.new(Sim.straight(8, workers: 2)), "Ada")
    world = Sim.walk(world, id, edge(world))

    workers = %{
      0 => %{cell: Grid.cell(world.grid, 12, @col), carry: 1, mode: :out, crossed: nil},
      1 => %{cell: Grid.cell(world.grid, 9, @col), carry: nil, mode: :out, crossed: nil}
    }

    assert {:ok, world} =
             World.lock(%{world | workers: workers}, id, Sim.river_cell(world, 1, @col))

    assert world.players[id].took == 1
    assert Map.keys(world.workers) == [0]
  end

  test "the nearest worker is the nearest by steps on foot, not in a straight line" do
    {world, id} = World.join(World.new(Sim.straight(8, workers: 2)), "Ada")
    grid = world.grid

    # A bridge of 3 bodies. Worker 0 is on the near bank, 4 steps from the new body.
    # Worker 1 is on the far bank: it is near in a straight line, but it has no way on foot.
    world =
      Enum.reduce(1..3, world, fn n, world ->
        Sim.lock!(world, id, Sim.river_cell(world, n, @col))
      end)

    world = Sim.walk(world, id, Sim.river_cell(world, 3, @col))

    workers = %{
      0 => %{cell: Grid.cell(grid, 13, @col), carry: nil, mode: :out, crossed: nil},
      1 => %{cell: Grid.cell(grid, 14 + 8, @col), carry: nil, mode: :out, crossed: nil}
    }

    assert {:ok, world} =
             World.lock(%{world | workers: workers}, id, Sim.river_cell(world, 4, @col))

    assert world.players[id].took == 0
  end

  test "with no free worker, the player is at the nest after 3 seconds" do
    {world, id} = World.join(World.new(Sim.straight(8)), "Ada")
    world = Sim.walk(world, id, edge(world))
    assert {:ok, world} = World.lock(world, id, Sim.river_cell(world, 1, @col))
    assert {:dead, _} = world.players[id].state

    world = Sim.run(world, 29)
    assert {:dead, _} = world.players[id].state
    {world, events} = World.tick(world)
    assert world.players[id].state == :alive
    assert world.players[id].cell == world.grid.nest
    assert [{^id, %{state: "alive"}}] = events.you
  end

  test "ten units of food at the nest make one worker" do
    world = World.new(Sim.cfg(workers: 8))
    {world, _} = World.take_events(world)

    world = Enum.reduce(1..9, world, fn _, world -> World.add_nest_food(world, 1, nil) end)
    assert map_size(world.workers) == 8
    world = World.add_nest_food(world, 1, nil)
    assert map_size(world.workers) == 9
    assert world.food_nest == 10

    # The new worker starts at the nest, and the clients get it.
    {world, events} = World.take_events(world)
    assert [{new, nest, 2}] = events.worker_set
    assert nest == world.grid.nest
    assert world.workers[new].cell == nest

    world = Enum.reduce(1..25, world, fn _, world -> World.add_nest_food(world, 1, nil) end)
    assert map_size(world.workers) == 11
  end

  test "the colony has 200 workers at most" do
    world = World.new(Sim.cfg(workers: 199))
    world = Enum.reduce(1..40, world, fn _, world -> World.add_nest_food(world, 1, nil) end)
    assert map_size(world.workers) == 200
  end

  test "with fewer than 5 free workers, the nest makes one worker each 10 seconds" do
    world = World.new(Sim.cfg(workers: 2))
    assert map_size(Sim.run(world, 99).workers) == 2
    assert map_size(Sim.run(world, 100).workers) == 3
    assert map_size(Sim.run(world, 200).workers) == 4
    assert map_size(Sim.run(world, 300).workers) == 5
    # With 5 free workers, the nest makes no more.
    assert map_size(Sim.run(world, 900).workers) == 5
  end

  test "the count of a locked body goes up when a free body goes on it" do
    {world, id} = World.join(World.new(Sim.straight(8)), "Ada")
    first = Sim.river_cell(world, 1, @col)
    world = Sim.lock!(world, id, first)
    assert world.locked[first].crossings == 0

    world = Sim.walk(world, id, first)
    assert world.locked[first].crossings == 1
    world = world |> Sim.walk(id, edge(world)) |> Sim.walk(id, first)
    assert world.locked[first].crossings == 2

    assert %{name: "Ada", crossings: 2, time: _, support: 84} = World.body(world, first)
    assert World.body(world, Sim.river_cell(world, 2, @col)) == nil
  end
end
