defmodule Colony.WorkersTest do
  @moduledoc "The rules of the workers: plan 0003, section 4.1."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  # The number of steps from a cell to the crossing place: the cells where a body can
  # stand and lock into an open cell.
  defp to_place(world, cell), do: Map.fetch!(world.front, cell)

  test "with no player and no helper, no body locks in 5 minutes, and the workers wait at the crossing place" do
    for seed <- 1..3 do
      world = World.new(Sim.cfg(seed: seed, workers: 30))

      {world, locks} =
        Enum.reduce(1..3000, {world, 0}, fn _, {world, locks} ->
          {world, events} = World.tick(world)
          {world, locks + length(events.locks)}
        end)

      assert locks == 0
      assert world.locked == %{}
      assert World.spare(world) == 30
      assert world.food_nest == 0

      # All the workers wait, on land 0, near the edge of the river and near the column
      # of the pile. One worker is on each cell.
      cells = for {_id, worker} <- world.workers, do: worker.cell
      assert Enum.all?(world.workers, fn {_id, worker} -> worker.mode == :wait end)

      assert Enum.all?(
               cells,
               &(Grid.land(world.grid, &1) == 0 and Grid.kind(world.grid, &1) == :land)
             )

      assert Enum.uniq(cells) == cells
      assert Enum.all?(cells, &(to_place(world, &1) <= 3))
      # The 13 open cells are 6 columns or less from the column of the pile. The 14 cells
      # of the edge of the land that touch them have a worker.
      col = world.piles[1].col

      assert Enum.sort(world.open) ==
               for(c <- (col - 6)..(col + 6), do: Sim.river_cell(world, 1, c))

      assert Enum.count(cells, &(to_place(world, &1) == 0)) == 14
      assert Enum.count(world.front, fn {_cell, steps} -> steps == 0 end) == 14
    end
  end

  test "one body locks 6 times across river 1: food is at the nest in less than 20 seconds" do
    cfg = Sim.cfg(workers: 30, rivers: [{6, 6}, {9, 11}, {12, 14}, {16, 18}])
    {world, id} = World.join(World.new(cfg), "Tester")
    # The player comes after one minute. The workers wait at the crossing place.
    world = Sim.run(world, 600)
    world = Sim.cross!(world, id, 1)
    assert length(World.bridge(world, 1)) == 6
    assert world.lock_count == 6
    assert world.food_nest == 0

    # The player does nothing more.
    {world, ticks} = Sim.run_until(world, 600, &(&1.food_nest > 0))
    assert ticks != nil
    IO.puts("\n  first food after the crossing of river 1: #{ticks / 10} s")
    assert ticks < 200
    assert world.lock_count == 6
    # The workers that waited on the bridge went across in a line.
    assert Sim.way_to_pile?(world, 1)
  end

  test "the workers that wait make a line on the bridge and a crowd behind it" do
    {world, id} = World.join(World.new(Sim.cfg(workers: 30)), "Tester")
    col = world.piles[1].col
    world = Sim.run(world, 300)
    world = Sim.lock!(world, id, Sim.river_cell(world, 1, col))
    world = Sim.lock!(world, id, Enum.min(world.open))
    world = Sim.lock!(world, id, Enum.min(world.open))
    world = Sim.run(world, 100)
    bridge = World.bridge(world, 1)

    # One worker waits on each body of the bridge. The other workers are on land 0.
    on_bridge = for {_id, worker} <- world.workers, worker.cell in bridge, do: worker.cell
    assert Enum.sort(on_bridge) == Enum.sort(bridge)
    assert World.spare(world) == 27

    # The next lock gives a body that is one step from the locked body.
    top = Enum.max(bridge)
    next = Enum.min(world.open)
    world = Sim.lock!(world, id, next)
    assert world.players[id].cell == top
  end

  test "when the workers can carry food, one worker of each three waits at the next crossing place" do
    {world, id} = World.join(World.new(Sim.cfg(workers: 31)), "Tester")
    world = world |> Sim.run(300) |> Sim.cross!(id, 1)
    assert World.spare(world) == 31 - length(World.bridge(world, 1))
    world = Sim.run(world, 600)

    spare = World.spare(world)
    waiting = Enum.count(world.workers, fn {_id, worker} -> worker.mode == :wait end)
    assert waiting == ceil(spare / 3)
    assert world.food_nest > 0

    # The workers that wait are at the edge of river 2, near the column of pile 2.
    edge = Grid.edge_row(world.grid, 2)
    col = world.piles[2].col

    # The workers that the nest made a moment before are on their way. The others are there.
    there =
      Enum.count(world.workers, fn {_id, worker} ->
        worker.mode == :wait and Grid.land(world.grid, worker.cell) == 1 and
          Grid.row(world.grid, worker.cell) >= edge - 2 and
          abs(Grid.col(world.grid, worker.cell) - col) <= 8
      end)

    assert there * 3 >= waiting * 2
  end

  test "a worker with food puts scent on the road, and no rule reads the scent" do
    {world, id} = World.join(World.new(Sim.cfg(workers: 30)), "Tester")
    world = world |> Sim.run(300) |> Sim.cross!(id, 1)
    {world, _} = Sim.run_until(world, 600, &(&1.food_nest >= 10))
    assert map_size(world.scent) > 10
    assert Enum.all?(world.scent, fn {_cell, value} -> value in 1..100 end)

    # With no scent, the workers do the same work.
    blank = Sim.run(%{world | scent: %{}}, 300)
    kept = Sim.run(world, 300)
    assert blank.food_nest == kept.food_nest
    assert blank.workers == kept.workers
  end

  test "with no pile that has food, the workers move near the nest" do
    world = World.new(Sim.straight(5, workers: 12))
    {world, id} = World.join(world, "Tester")
    world = Sim.cross!(world, id, 1)
    # The pile is empty.
    world = %{world | piles: Map.update!(world.piles, 1, &%{&1 | units: 0})}
    world = Sim.run(world, 600)

    for {_id, worker} <- world.workers do
      assert worker.mode == :idle
      assert Grid.land(world.grid, worker.cell) == 0
      assert Grid.nest_distance(world.grid, worker.cell) <= 6
    end
  end

  test "a new pile calls 3 workers until its first food is at the nest" do
    # Two rivers. The colony has no worker at the last crossing: the player used them all.
    cfg = Sim.cfg(workers: 14, rivers: [{5, 5}, {9, 9}], workers_low: 0)
    {world, id} = World.join(World.new(cfg), "Tester")
    world = world |> Sim.cross!(id, 1) |> Sim.cross!(id, 2)
    world = %{world | workers: %{}}
    refute world.piles[2].fed

    # The nest gets food from a player: new workers. Pile 1 is nearer to the nest, but 3
    # workers go to pile 2.
    world = World.add_nest_food(world, 1, 30)
    assert World.spare(world) == 10
    world = Sim.run(world, 5)
    called = for {_id, %{mode: {:fetch, 2}}} = entry <- world.workers, do: entry
    assert length(called) == 3

    {world, ticks} = Sim.run_until(world, 1200, &(&1.complete != nil))
    assert ticks != nil
    assert world.piles[2].fed
    # After the first food, no worker is called: the workers go to the nearest pile.
    world = Sim.run(world, 100)
    assert Enum.all?(world.workers, fn {_id, worker} -> not match?({:fetch, _}, worker.mode) end)
  end

  describe "the workers of the nest" do
    test "5 units of food at the nest make one worker" do
      world = World.new(Sim.cfg(workers: 10, food_per_worker: 5))
      world = Enum.reduce(1..4, world, fn _, world -> World.add_nest_food(world, 1, 1) end)
      assert World.spare(world) == 10
      world = World.add_nest_food(world, 1, 1)
      assert World.spare(world) == 11
      # The new worker is at the nest.
      assert Enum.any?(world.workers, fn {_id, worker} -> worker.cell == world.grid.nest end)
      assert world.food_nest == 5
    end

    test "the colony has 200 workers at most" do
      world = World.new(Sim.cfg(workers: 199))
      world = World.add_nest_food(world, 1, 50)
      assert World.spare(world) == 200
    end

    test "with fewer than 5 spare bodies, the nest makes one worker each 10 seconds" do
      world = World.new(Sim.cfg(workers: 2))
      world = Sim.run(world, 100)
      assert World.spare(world) == 3
      world = Sim.run(world, 200)
      assert World.spare(world) == 5
      world = Sim.run(world, 300)
      assert World.spare(world) == 5
    end
  end
end
