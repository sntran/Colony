defmodule Colony.PileTest do
  @moduledoc "The piles, the food that a player carries, and the records: plan 0003, 4.3, 4.6 and 4.7."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Protocol, Sim, World}

  describe "the piles" do
    test "pile 1 is on land 1, 3 rows after the river, 10 columns or less from the nest" do
      columns =
        for seed <- 1..40 do
          world = World.new(Sim.cfg(seed: seed))
          grid = world.grid
          assert Map.keys(world.piles) == [1]
          pile = world.piles[1]
          assert abs(pile.col - 30) <= 10
          assert Grid.col(grid, pile.cell) == pile.col
          assert Grid.land(grid, pile.cell) == 1 and Grid.kind(grid, pile.cell) == :land

          row = Grid.river_start(grid, 1) + Grid.river_width(grid, 1, pile.col) + 2
          assert Grid.row(grid, pile.cell) == row
          assert {pile.size, pile.units} == {300, 300}
          pile.col
        end

      # The column is random.
      assert length(Enum.uniq(columns)) > 10
    end

    test "a pile that no body can walk to loses 1 unit each second, down to 50 units" do
      world = World.new(Sim.cfg())
      assert Sim.run(world, 100).piles[1].units == 290
      assert Sim.run(world, 2000).piles[1].units == 100
      assert Sim.run(world, 2500).piles[1].units == 50
      assert Sim.run(world, 4000).piles[1].units == 50
    end

    test "at the crossing, the loss stops for always and the next pile appears" do
      {world, id} = World.join(World.new(Sim.cfg(workers: 200, workers_low: 0)), "Tester")
      world = Sim.cross!(world, id, 1)
      units = world.piles[1].units
      assert units < 300
      assert world.piles[1].crossed != nil
      assert Sim.way_to_pile?(world, 1)

      # Pile 2 is on land 2, in a column that is 10 or more from each edge.
      grid = world.grid
      pile = world.piles[2]
      assert {pile.size, pile.units} == {400, 400}
      assert pile.col in 10..49
      assert Grid.land(grid, pile.cell) == 2

      assert Grid.row(grid, pile.cell) ==
               Grid.river_start(grid, 2) + Grid.river_width(grid, 2, pile.col) + 2

      refute Sim.way_to_pile?(world, 2)

      # With no worker, pile 1 keeps its units. Pile 2 loses 1 unit each second.
      world = %{world | workers: %{}}
      later = Sim.run(world, 300)
      assert later.piles[1].units == units
      assert later.piles[2].units == 370
    end

    test "the sizes are 300, 400, 500 and 600 units, and there is no pile after land 4" do
      {world, id} = World.join(World.new(Sim.cfg(workers: 200, workers_max: 400)), "Tester")

      world =
        Enum.reduce(1..4, world, fn k, world ->
          assert Map.keys(world.piles) == Enum.to_list(1..k)
          world = Sim.cross!(world, id, k)
          assert World.complete?(world, k)
          world
        end)

      assert Enum.map(1..4, &world.piles[&1].size) == [300, 400, 500, 600]
      assert map_size(world.piles) == 4
      assert world.stage == 5
      assert World.far_pile(world) == nil
      assert MapSet.size(world.open) == 0

      # The later piles are in random columns: two seeds give different columns.
      {other, id} = World.join(World.new(Sim.cfg(workers: 200, seed: 2)), "Tester")
      other = Sim.cross!(other, id, 1)
      assert other.piles[2].col != world.piles[2].col or other.piles[1].col != world.piles[1].col
    end
  end

  describe "a player carries food" do
    setup do
      {world, id} = World.join(World.new(Sim.cfg(workers: 20, rivers: [{5, 5}, {9, 9}])), "Tester")
      world = Sim.cross!(world, id, 1)

      %{
        world: %{world | workers: Map.take(world.workers, Enum.take(Map.keys(world.workers), 3))},
        id: id
      }
    end

    test "a player who touches a pile takes 10 units, and the new workers are there at the nest",
         %{world: world, id: id} do
      units = world.piles[1].units
      spare = World.spare(world)
      # The workers of this test do not move.
      still = %{world | p: %{world.p | step: 0.0}}
      world = %{Sim.walk(%{still | p: world.p}, id, world.piles[1].cell) | workers: world.workers}
      world = Sim.run(%{world | p: %{world.p | step: 0.0}}, 1)
      assert world.players[id].carry == %{pile: 1, units: 10}
      assert world.piles[1].units <= units - 10

      # The body does not take more food while it carries food.
      assert Sim.run(world, 10).players[id].carry == %{pile: 1, units: 10}

      world = %{world | p: %{world.p | step: 0.4}}
      food = world.food_nest
      credit = world.food_credit
      world = Sim.walk(world, id, world.grid.nest)
      world = Sim.run(world, 1)
      assert world.players[id].carry == nil
      assert world.food_nest >= food + 10
      # 5 units make one worker: 10 units make 2 workers, immediately.
      assert World.spare(world) >= spare + 2
      assert world.food_by[{"Tester", false}] == 10
      assert credit in 0..4
    end

    test "a player takes all the units if fewer than 10 are there", %{world: world, id: id} do
      world = %{world | workers: %{}, piles: Map.update!(world.piles, 1, &%{&1 | units: 4})}
      world = Sim.walk(world, id, world.piles[1].cell)
      world = Sim.run(world, 1)
      assert world.players[id].carry == %{pile: 1, units: 4}
      assert world.piles[1].units == 0

      # An empty pile gives nothing.
      {world, other} = World.join(world, "Other")
      world = Sim.walk(world, other, world.piles[1].cell)
      assert Sim.run(world, 5).players[other].carry == nil
    end
  end

  describe "a record" do
    setup do
      cfg = Sim.cfg(workers: 60, rivers: [{6, 6}, {9, 9}])
      {world, ann} = World.join(World.new(cfg), "Ann")
      {world, bob} = World.join(world, "Bob")
      world = Sim.run(world, 50)
      col = world.piles[1].col
      world = Sim.lock!(world, ann, Sim.river_cell(world, 1, col))
      world = Sim.run(world, 70)

      world =
        Enum.reduce(1..3, world, fn _, world -> Sim.lock!(world, bob, Enum.min(world.open)) end)

      world =
        Enum.reduce(1..2, world, fn _, world -> Sim.lock!(world, ann, Enum.min(world.open)) end)

      %{world: world, ann: ann, bob: bob}
    end

    test "the crossing makes a record with the names, the bodies, the food of the pile and the seconds",
         %{world: world} do
      assert world.stage == 2
      assert [record] = world.records
      assert record.id == 1
      assert record.bodies == 6
      assert record.rows == 6
      assert record.width == 6

      assert record.names == [
               %{name: "Ann", helper: false, bodies: 3, food: 0},
               %{name: "Bob", helper: false, bodies: 3, food: 0}
             ]

      # The pile lost 1 unit each second from the start of the world to the crossing.
      assert record.size == 300
      assert record.left == 300 - world.piles[1].crossed
      # The seconds are from the first lock of the bridge to the crossing.
      assert record.seconds == world.piles[1].crossed - world.first_lock[1]
      assert record.seconds >= 7
      assert JSON.decode!(JSON.encode!(Protocol.record(record)))["names"] |> length() == 2
    end

    test "each client gets the record at the crossing", %{world: world, ann: ann} do
      {world, _} = World.take_events(world)
      world = Sim.cross!(world, ann, 2)
      {_world, events} = World.take_events(world)
      assert [%{id: 2, first: true, bodies: bodies, left: left, size: 400}] = events.records
      assert bodies >= 10
      assert left < 400
    end

    test "the record of a bridge counts the food that each player carried before its crossing",
         %{world: world, ann: ann, bob: bob} do
      # Bob carries food two times while Ann builds the bridge of river 2.
      world =
        Enum.reduce(1..2, world, fn _, world ->
          world = Sim.walk(world, bob, world.piles[1].cell)
          world = Sim.run(world, 1)
          assert world.players[bob].carry.units == 10
          Sim.run(Sim.walk(world, bob, world.grid.nest), 1)
        end)

      world = Sim.cross!(world, ann, 2)
      [second, first] = world.records
      assert first.id == 1 and second.id == 2
      assert %{name: "Bob", helper: false, bodies: 0, food: 20} in second.names
      assert Enum.find(second.names, &(&1.name == "Ann")).bodies == second.bodies
      # The first record does not change.
      assert Enum.all?(first.names, &(&1.food == 0))

      # After the last crossing, the food counts in the last record, and the clients get
      # the record again.
      {world, _} = World.take_events(world)
      world = World.add_nest_food(world, 1, 10, {"Bob", false})

      {world, records} =
        Enum.reduce(1..12, {world, []}, fn _, {world, records} ->
          {world, events} = World.tick(world)
          {world, records ++ events.records}
        end)

      assert [%{id: 2} = sent] = records
      refute Map.has_key?(sent, :first)
      assert %{name: "Bob", helper: false, bodies: 0, food: 30} in sent.names
      assert world.food_by[{"Bob", false}] == 30
    end
  end

  describe "the end of the world" do
    test "the world is complete at the first food of pile 4" do
      {world, id} = World.join(World.new(Sim.cfg(workers: 200, workers_max: 400)), "Tester")
      world = Enum.reduce(1..4, world, fn k, world -> Sim.cross!(world, id, k) end)
      assert world.complete == nil
      units = world.piles[4].units

      # Food of pile 1 gets to the nest first: the world is not complete.
      {world, _} = Sim.run_until(world, 3000, &(&1.food_nest > 0))
      assert world.piles[1].units < 300
      assert world.complete == nil

      {world, ticks} = Sim.run_until(world, 6000, &(&1.complete != nil))
      assert ticks != nil
      assert world.piles[4].units < units
      assert world.complete == world.now
      # The world continues after its end.
      later = Sim.run(world, 100)
      assert later.complete == world.complete
      assert later.tick == world.tick + 100
    end

    test "the story has all the locks in the order of their times, with the names" do
      cfg = Sim.cfg(workers: 60, rivers: [{6, 6}, {9, 9}])
      {world, ann} = World.join(World.new(cfg), "Ann")
      {world, bob} = World.join(world, "Bob")
      world = Sim.cross!(world, ann, 1)
      world = Sim.lock!(world, bob, Enum.min(world.open))
      world = Sim.cross!(world, ann, 2)
      story = World.story(world)

      assert Enum.map(story.locks, & &1.n) == Enum.to_list(1..map_size(world.locked))
      assert Enum.map(story.locks, & &1.time) == Enum.sort(Enum.map(story.locks, & &1.time))
      assert Enum.map(story.locks, & &1.river) |> Enum.dedup() == [1, 2]
      assert Enum.at(story.locks, 6).name == "Bob"
      assert story.crossings == 2
      assert [%{name: "Ann", bodies: ann_bodies}, %{name: "Bob", bodies: 1, food: 0}] = story.names
      assert ann_bodies == map_size(world.locked) - 1
      assert JSON.decode!(JSON.encode!(story))["locks"] |> length() == map_size(world.locked)
    end
  end
end
