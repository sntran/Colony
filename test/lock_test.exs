defmodule Colony.LockTest do
  @moduledoc "A lock: only into an open cell, and only with a spare body. Plan 0003, 4.4 and 4.5."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  # A world with the rivers of the game, 10 spare bodies and one player.
  defp start(changes \\ []) do
    {world, id} = World.join(World.new(Sim.cfg(Keyword.merge([spare: 10], changes))), "Tester")
    %{world: world, id: id, col: world.piles[1].col}
  end

  describe "where a lock is possible" do
    test "a lock into a cell that is not open gets an error" do
      %{world: world, id: id, col: col} = start()
      edge = Grid.cell(world.grid, 13, col + 9)
      world = Sim.walk(world, id, edge)

      # A cell of the first row, more than 6 columns from the column of the pile. A body
      # there has support, but the cell is not open.
      far = Sim.river_cell(world, 1, col + 9)
      assert far in Grid.neighbors(world.grid, edge)
      refute World.open?(world, far)
      assert {{:error, :not_possible}, ^world} = World.lock(world, id, far)

      # After the first lock, a cell of the first row that does not touch the bridge is
      # not open.
      world = Sim.lock!(world, id, Sim.river_cell(world, 1, col))
      other = Sim.river_cell(world, 1, col + 3)
      assert {{:error, :not_possible}, _} = Sim.walk_and_lock(world, id, other)

      # A land cell, a cell with a body, a cell that is not on the grid, and a value that
      # is not a cell.
      for cell <- [edge, Sim.river_cell(world, 1, col), 70_000, -1, "8", nil] do
        assert {{:error, :not_possible}, _} = World.lock(world, id, cell)
      end
    end

    test "a lock with no spare body gets an error" do
      %{world: world, id: id, col: col} = start(spare: 1)
      assert World.spare(world) == 1
      world = Sim.lock!(world, id, Sim.river_cell(world, 1, col))
      assert World.spare(world) == 0

      # The cell is open, and the body touches it. Only the spare body is not there.
      world = Sim.wait_ready(world, id)
      [cell | _] = Sim.open(world)
      world = Sim.walk(world, id, Sim.river_cell(world, 1, col))
      assert cell in Grid.neighbors(world.grid, world.players[id].cell)
      assert {{:error, :not_possible}, _} = World.lock(world, id, cell)

      # The nest makes a worker after 10 seconds. Then the lock is possible.
      {world, ticks} = Sim.run_until(world, 150, &(World.spare(&1) == 1))
      assert ticks <= 101
      assert {:ok, world} = World.lock(world, id, cell)
      assert World.spare(world) == 0
    end

    test "a body cannot lock into a cell that does not touch its cell" do
      %{world: world, id: id, col: col} = start()
      cell = Sim.river_cell(world, 1, col)
      assert World.open?(world, cell)
      # The body is at the nest.
      assert {{:error, :not_possible}, _} = World.lock(world, id, cell)
    end

    test "two bodies lock into the same cell in the same tick: one gets the cell" do
      %{world: world, id: one, col: col} = start()
      {world, two} = World.join(world, "Second")
      cell = Sim.river_cell(world, 1, col)
      edge = Grid.cell(world.grid, 13, col)
      world = world |> Sim.walk(one, edge) |> Sim.walk(two, edge)
      tick = world.tick

      assert {:ok, world} = World.lock(world, one, cell)
      assert {{:error, :not_possible}, world} = World.lock(world, two, cell)
      assert world.tick == tick
      assert world.locked[cell].name == "Tester"
      assert map_size(world.locked) == 1
      # Only one spare body is used. The second player keeps its body.
      assert World.spare(world) == 9
      assert world.players[two].cell == edge
    end
  end

  describe "the new body of the player" do
    test "a lock uses one spare body: the player has the body of the nearest worker" do
      %{world: world, id: id, col: col} = start()
      # The spare bodies go to the crossing place.
      world = Sim.run(world, 300)
      cell = Sim.river_cell(world, 1, col)
      edge = Grid.cell(world.grid, 13, col)
      world = Sim.walk(world, id, edge)
      cells = for {_id, worker} <- world.workers, do: worker.cell
      steps = fn at -> length(Sim.path(world, edge, at)) end
      nearest = cells |> Enum.map(steps) |> Enum.min()

      {:ok, after_lock} = World.lock(world, id, cell)
      player = after_lock.players[id]
      assert World.spare(after_lock) == 9
      assert player.took != nil
      refute is_map_key(after_lock.workers, player.took)
      assert player.cell == world.workers[player.took].cell
      # The lock is a new step on foot: the nearest worker from the locked body.
      assert length(Sim.path(after_lock, cell, player.cell)) <= nearest + 1
      {x, z} = Grid.center(world.grid, player.cell)
      assert {player.x, player.z} == {x, z}
    end

    test "a body that a player took cannot lock for 1 second" do
      %{world: world, id: id, col: col} = start()
      world = Sim.run(world, 300)
      world = Sim.lock!(world, id, Sim.river_cell(world, 1, col))
      tick = world.tick
      assert world.players[id].ready_tick == tick + 10

      # The player goes to the bridge immediately, and the lock is refused until the
      # second is at its end.
      [next | _] = Sim.open(world)
      first = Sim.river_cell(world, 1, col)
      path = Sim.path(world, world.players[id].cell, first)
      assert length(path) <= 3

      world =
        Enum.reduce(path, world, fn cell, world ->
          {x, z} = Grid.center(world.grid, cell)
          world |> World.move(id, x, z, 0.0) |> Sim.run(3)
        end)

      assert world.players[id].cell == first
      assert world.tick < tick + 10
      assert {{:error, :not_possible}, _} = World.lock(world, id, next)
      world = Sim.run(world, tick + 10 - world.tick)
      assert {:ok, _} = World.lock(world, id, next)
    end

    test "a player who joins gets a body at the nest, and this uses no spare body" do
      %{world: world, id: id} = start()
      assert World.spare(world) == 10
      assert world.players[id].cell == world.grid.nest
      {world, other} = World.join(world, "Other")
      assert World.spare(world) == 10
      assert world.players[other].cell == world.grid.nest
    end
  end

  describe "where a free body can go" do
    test "a free body cannot go into the river" do
      %{world: world, id: id, col: col} = start()
      edge = Grid.cell(world.grid, 13, col)
      world = Sim.walk(world, id, edge)
      {x, z} = Grid.center(world.grid, Sim.river_cell(world, 1, col))
      {world, _} = World.take_events(world)
      world = World.move(world, id, x, z, 0.0)
      assert world.players[id].cell == edge
      {_world, events} = World.take_events(world)
      assert [{^id, %{x: _, z: _}}] = events.you
    end

    test "a free body cannot jump across a cell where a body cannot be" do
      %{world: world, id: id, col: col} = start(rivers: [{7, 7}])
      world = Sim.lock!(world, id, Sim.river_cell(world, 1, col))
      world = Sim.lock!(world, id, hd(Sim.open(world)))
      world = Sim.lock!(world, id, hd(Sim.open(world)))
      [first, second, third] = Enum.sort(World.bridge(world, 1))
      world = Sim.walk(world, id, first)
      # The body waits and gets all the movement that the world lets it keep.
      world = Sim.run(world, 20)

      # To the cell that does not touch: the world refuses.
      {x, z} = Grid.center(world.grid, third)
      assert World.move(world, id, x, z, 0.0).players[id].cell == first

      # With a hole in the bridge, the body cannot go across the hole in two moves.
      hole = %{world | locked: Map.delete(world.locked, second)}
      {x2, z2} = Grid.center(world.grid, second)
      assert World.move(hole, id, x2, z2, 0.0).players[id].cell == first
      world = World.move(world, id, x2, z2, 0.0)
      assert world.players[id].cell == second
    end

    test "a body on the edge of its cell stands on that cell" do
      %{world: world, id: id, col: col} = start()
      # A position in a message has a step of 0.002. On the edge of a cell, the position
      # can be a very small distance in the river.
      edge = Grid.cell(world.grid, 13, col)
      world = Sim.walk(world, id, edge)
      {x, z} = Grid.center(world.grid, edge)
      tip = z + 1 / :math.sqrt(3)

      world = World.move(world, id, x, tip - 0.001, 0.0)
      assert_in_delta world.players[id].z, tip - 0.001, 1.0e-9
      world = world |> Sim.run(3) |> World.move(id, x, tip + 0.002, 0.0)
      assert_in_delta world.players[id].z, tip + 0.002, 1.0e-9
      assert world.players[id].cell == edge

      # A larger distance in the river is not possible.
      world = world |> Sim.run(3) |> World.move(id, x, tip + 0.02, 0.0)
      assert_in_delta world.players[id].z, tip + 0.002, 1.0e-9
    end

    test "a locked body stays: no rule removes it" do
      %{world: world, id: id} = start(spare: 30)
      world = Sim.cross!(world, id, 1)
      bodies = Map.keys(world.locked)
      world = world |> World.leave(id) |> Sim.run(3000)
      assert Map.keys(world.locked) == bodies
    end

    test "the count of a locked body goes up when a free body goes on it" do
      %{world: world, id: id, col: col} = start()
      cell = Sim.river_cell(world, 1, col)
      world = Sim.lock!(world, id, cell)
      before = World.body(world, cell).crossings
      world = Sim.walk(world, id, cell)
      assert World.body(world, cell).crossings > before
      assert World.body(world, cell).name == "Tester"
      assert World.body(world, cell).support == 84
      assert World.body(world, Grid.cell(world.grid, 13, col)) == nil
    end
  end
end
