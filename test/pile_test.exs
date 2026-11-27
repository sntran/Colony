defmodule Colony.PileTest do
  @moduledoc """
  The piles, the food that a player carries, the records and the end of a world with an end:
  plan 0004, 4.3 and 4.5, and plan 0003, 4.6 and 4.7.
  """

  use ExUnit.Case, async: true

  alias Colony.{Grid, Protocol, Sim, World}

  @table_best %{11 => 16, 14 => 25, 18 => 41}
  @table_random %{11 => 19, 14 => 34, 18 => 54}

  describe "the piles" do
    test "pile 1 is on land 1, 3 rows after the river, 10 columns or less from the nest" do
      columns =
        for seed <- 1..40 do
          world = World.new(Sim.cfg(seed: seed))
          grid = world.grid
          assert Map.keys(world.piles) == [1]
          pile = world.piles[1]
          assert abs(pile.col - 30) <= 10
          assert Grid.land(grid, pile.cell) == 1 and Grid.kind(grid, pile.cell) == :land
          row = Grid.river_start(grid, 1) + Grid.river_width(grid, 1, pile.col) + 2
          assert Grid.row(grid, pile.cell) == row
          pile.col
        end

      # The column is random.
      assert length(Enum.uniq(columns)) > 10
    end

    test "the sizes and the least units of the piles come from the table of the open cells" do
      world = World.new(Sim.cfg())
      # The config has the numbers of the table: see test/open_test.exs.
      for {width, best} <- @table_best, do: assert(world.p.bridge_best[width] == best)
      for {width, random} <- @table_random, do: assert(world.p.bridge_random[width] == random)

      # Pile k pays for the bridge across river k + 1: 5 * 1.5 * R and 5 * 1.1 * B for the
      # largest width of that river. The last pile of the world with an end has 600 units.
      assert World.pile_size(world, 1) == {round(5 * 1.5 * 19), round(5 * 1.1 * 16)}
      assert World.pile_size(world, 2) == {round(5 * 1.5 * 34), round(5 * 1.1 * 25)}
      assert World.pile_size(world, 3) == {round(5 * 1.5 * 54), round(5 * 1.1 * 41)}
      assert World.pile_size(world, 4) == {600, 50}
      assert World.pile_size(world, 1) == {143, 88}

      {world, id} = World.join(World.new(Sim.cfg(spare: 200)), "Tester")
      world = Enum.reduce(1..4, world, fn k, world -> Sim.cross!(world, id, k) end)

      for k <- 1..4 do
        {size, least} = World.pile_size(world, k)
        assert world.piles[k].size == size
        assert world.piles[k].least == least
      end
    end

    test "a pile that no body can walk to loses 1 unit each second, down to its least units" do
      world = World.new(Sim.cfg())
      assert Sim.run(world, 100).piles[1].units == 133
      assert Sim.run(world, 500).piles[1].units == 93
      assert Sim.run(world, 600).piles[1].units == 88
      assert Sim.run(world, 2000).piles[1].units == 88
    end

    test "at the crossing, the loss stops and the next pile appears 12 columns or less from the pile before it" do
      for seed <- 1..12 do
        cfg = Sim.cfg(spare: 200, carriers: 0, carriers_per_crossing: 0, spare_low: 0, seed: seed)
        {world, id} = World.join(World.new(cfg), "Tester")
        world = Sim.cross!(world, id, 1)
        units = world.piles[1].units
        assert world.piles[1].crossed != nil
        assert Sim.way_to_pile?(world, 1)

        grid = world.grid
        pile = world.piles[2]
        assert pile.col in 10..49
        assert abs(pile.col - world.piles[1].col) <= 12
        assert Grid.land(grid, pile.cell) == 2
        refute Sim.way_to_pile?(world, 2)

        # With no worker, pile 1 keeps its units. Pile 2 loses 1 unit each second.
        later = Sim.run(%{world | workers: %{}}, 300)
        assert later.piles[1].units == units
        assert later.piles[2].units == pile.size - 30
      end
    end
  end

  describe "a player carries food" do
    setup do
      cfg = Sim.cfg(spare: 20, carriers: 0, carriers_per_crossing: 0, rivers: [{5, 5}, {9, 9}])
      {world, id} = World.join(World.new(cfg), "Tester")
      %{world: Sim.cross!(world, id, 1), id: id}
    end

    test "a player who touches a pile takes 10 units, and the new spare bodies come out of the nest at once",
         %{world: world, id: id} do
      units = world.piles[1].units
      spare = World.spare(world)
      world = Sim.walk(world, id, world.piles[1].cell)
      world = Sim.run(world, 1)
      assert world.players[id].carry == %{pile: 1, units: 10}
      assert world.piles[1].units == units - 10
      # The body does not take more food while it carries food.
      assert Sim.run(world, 10).players[id].carry == %{pile: 1, units: 10}

      # The food goes into the nest in the tick when the body gets near the nest.
      {world, _ticks} =
        Enum.reduce_while(Sim.path(world, world.players[id].cell, world.nest), {world, 0}, fn cell,
                                                                                              {world,
                                                                                               n} ->
          world = Sim.walk(world, id, cell)
          if world.players[id].carry == nil, do: {:halt, {world, n}}, else: {:cont, {world, n + 1}}
        end)

      assert world.players[id].carry == nil
      assert world.food_nest == 10
      # 5 units make one spare body: 10 units make 2 spare bodies, at once, at the nest.
      assert World.spare(world) == spare + 2

      new =
        for {_id, w} <- Sim.workers(world, :spare),
            Grid.distance(world.grid, w.cell, world.nest) <= 1,
            do: w

      assert length(new) >= 2
      assert world.people[world.players[id].person].food == 10
      assert world.players[id].last == :carry
    end

    test "a player with food cannot lock", %{world: world, id: id} do
      world = Sim.walk(world, id, world.piles[1].cell)
      world = Sim.run(world, 1)
      assert world.players[id].carry != nil
      [cell | _] = Sim.open(world)
      stand = world.grid |> Grid.neighbors(cell) |> Enum.find(&World.walkable?(world, &1))
      world = Sim.walk(world, id, stand)
      spare = World.spare(world)
      assert {{:error, :not_possible}, world} = World.lock(world, id, cell)
      assert World.spare(world) == spare
      # The food stays with the body.
      assert world.players[id].carry.units == 10

      # After the food is at the nest, the lock is possible.
      world = Sim.walk(world, id, world.nest)
      world = Sim.run(world, 1)
      world = Sim.walk(world, id, stand)
      assert {:ok, _world} = World.lock(world, id, cell)
    end

    test "a player takes all the units if fewer than 10 are there", %{world: world, id: id} do
      world = %{world | piles: Map.update!(world.piles, 1, &%{&1 | units: 4})}
      world = Sim.walk(world, id, world.piles[1].cell)
      world = Sim.run(world, 1)
      assert world.players[id].carry == %{pile: 1, units: 4}
      assert world.piles[1].units == 0
    end
  end

  describe "a record" do
    setup do
      cfg = Sim.cfg(spare: 60, rivers: [{6, 6}, {9, 9}])
      {world, ann} = World.join(World.new(cfg), "Ann")
      {world, bob} = World.join(world, "Bob")
      world = Sim.run(world, 50)
      col = world.piles[1].col
      world = Sim.lock!(world, ann, Sim.river_cell(world, 1, col))
      world = Sim.run(world, 70)

      world =
        Enum.reduce(1..3, world, fn _, world -> Sim.lock!(world, bob, hd(Sim.open(world))) end)

      world =
        Enum.reduce(1..2, world, fn _, world -> Sim.lock!(world, ann, hd(Sim.open(world))) end)

      %{world: world, ann: ann, bob: bob}
    end

    test "the crossing makes a record with the names, the bodies, the best bridge, the food of the pile and the seconds",
         %{world: world, ann: ann, bob: bob} do
      assert world.stage == 2
      assert [record] = world.records
      assert record.id == 1
      assert record.bodies == 6
      assert record.rows == 6
      assert record.width == 6
      # The best bridge across 6 rows has 6 bodies.
      assert record.best == 6

      assert record.names == [
               %{name: "Ann", helper: false, owner: world.players[ann].person, bodies: 3, food: 0},
               %{name: "Bob", helper: false, owner: world.players[bob].person, bodies: 3, food: 0}
             ]

      {size, least} = World.pile_size(world, 1)
      assert record.size == size
      assert record.left == max(least, size - world.piles[1].crossed)
      assert record.seconds == world.piles[1].crossed - world.first_lock[1]
      json = JSON.decode!(JSON.encode!(Protocol.record(record)))
      assert json["best"] == 6 and length(json["names"]) == 2
    end

    test "the record of a bridge counts the food that each player carried before its crossing",
         %{world: world, ann: ann, bob: bob} do
      world = Enum.reduce(1..2, world, fn _, world -> Sim.carry!(world, bob, 1) end)
      world = Sim.cross!(world, ann, 2)
      [second, first] = world.records
      assert first.id == 1 and second.id == 2
      bob_person = world.players[bob].person
      assert %{name: "Bob", helper: false, owner: bob_person, bodies: 0, food: 20} in second.names
      assert Enum.all?(first.names, &(&1.food == 0))
    end
  end

  describe "the end of a world with an end" do
    test "the world is complete at the first food of the last pile" do
      {world, id} = World.join(World.new(Sim.cfg(spare: 200, carriers: 12)), "Tester")
      world = Enum.reduce(1..4, world, fn k, world -> Sim.cross!(world, id, k) end)
      assert world.complete == nil
      assert map_size(world.open) == 0

      {world, ticks} = Sim.run_until(world, 6000, &(&1.complete != nil))
      assert ticks != nil
      assert world.piles[4].fed
      later = Sim.run(world, 100)
      assert later.complete == world.complete
    end

    test "the story has all the locks in the order of their times, with the names, the food and the walks" do
      {world, ann} = World.join(World.new(Sim.cfg(spare: 60, rivers: [{6, 6}, {9, 9}])), "Ann")
      {world, bob} = World.join(world, "Bob")
      world = Sim.cross!(world, ann, 1)
      world = Sim.lock!(world, bob, hd(Sim.open(world)))
      world = Sim.cross!(world, ann, 2)
      story = World.story(world)

      assert Enum.map(story.locks, & &1.n) == Enum.to_list(1..map_size(world.locked))
      assert Enum.map(story.locks, & &1.river) |> Enum.dedup() == [1, 2]
      assert Enum.at(story.locks, 6).name == "Bob"
      assert story.crossings == 2

      assert [%{name: "Ann", bodies: ann_bodies, walks: walks}, %{name: "Bob", bodies: 1, food: 0}] =
               story.names

      assert ann_bodies == map_size(world.locked) - 1
      assert walks > 0
      assert JSON.decode!(JSON.encode!(story))["locks"] |> length() == map_size(world.locked)
    end
  end
end
