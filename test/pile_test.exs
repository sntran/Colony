defmodule Colony.PileTest do
  @moduledoc "Plan 0002, sections 4.2 and 4.8: the piles of food and the records of the bridges."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  describe "the first pile" do
    test "is across the narrowest place, 3 rows from the river" do
      for seed <- 1..10 do
        world = World.new(Sim.cfg(seed: seed))
        grid = world.grid
        pile = world.pile
        narrow = grid.river |> Tuple.to_list() |> Enum.min()

        assert pile.id == 1
        assert pile.units == 300
        assert pile.width == narrow
        assert Grid.river_width(grid, pile.col) == narrow
        assert Grid.kind(grid, pile.cell) == :far
        assert Grid.row(grid, pile.cell) == 14 + narrow + 2
        assert abs(pile.col - 30) <= 6
      end
    end
  end

  describe "the loss of a pile" do
    test "a pile loses no unit before the first lock" do
      world = World.new(Sim.cfg()) |> Sim.run(600)
      assert world.pile.units == 300
    end

    test "a pile loses 1 unit each second from the first lock to the first food" do
      {world, id} = World.join(World.new(Sim.cfg()), "Ada")
      world = Sim.lock!(world, id, Sim.river_cell(world, 1, 30))
      units = world.pile.units
      assert world.pile.first_lock != nil

      world = Sim.run(world, 200)
      assert world.pile.units == units - 20

      # The first worker that takes food stops the loss.
      world = World.take_food(world)
      assert world.pile.units == units - 21
      assert Sim.run(world, 200).pile.units == units - 21
    end

    test "a pile with 0 units makes the next pile across a wider place" do
      {world, id} = World.join(World.new(Sim.cfg(pile_units: 5)), "Ada")
      first = world.pile
      world = Sim.lock!(world, id, Sim.river_cell(world, 1, 30))
      {world, ticks} = Sim.run_until(world, 100, &(&1.pile.id == 2))
      assert ticks != nil

      second = world.pile
      assert second.units == 5
      assert second.width == 9
      assert second.col != first.col
      assert second.first_lock == nil
      assert Grid.kind(world.grid, second.cell) == :far
      assert world.history[1].width == first.width
    end

    test "the widths of the piles are about 6, 9, 12, 14 and 16 rows, then random" do
      world = World.new(Sim.cfg(pile_units: 1, seed: 4))

      {_world, widths} =
        Enum.reduce(1..8, {world, [world.pile.width]}, fn _, {world, widths} ->
          world = World.take_food(world)
          {world, widths ++ [world.pile.width]}
        end)

      assert [first, 9, 12, 14, 16 | random] = widths
      assert first in [5, 6]
      assert length(random) == 4
    end

    test "a new pile is 8 columns or more from each complete bridge" do
      # A river of 6 rows in all its columns: each place is as good as each other place.
      {world, id} = World.join(World.new(Sim.straight(6, pile_units: 1)), "Ada")
      col = world.pile.col

      world =
        Enum.reduce(1..6, world, fn n, world ->
          Sim.lock!(world, id, Sim.river_cell(world, n, col))
        end)

      assert [bridge] = World.bridges(world)
      assert World.complete?(world, bridge)

      for _ <- 1..30, reduce: world do
        world ->
          world = World.take_food(world)
          assert abs(world.pile.col - col) >= 8
          world
      end
    end
  end

  describe "a record" do
    # A player builds a bridge of 6 bodies across a river of 6 rows, with scent on the way.
    # Then the workers carry the food of a small pile.
    defp colony(units) do
      {world, id} = World.join(World.new(Sim.straight(6, workers: 20, pile_units: units)), "Ada")
      col = world.pile.col
      nest_col = Grid.col(world.grid, world.grid.nest)

      # The player goes along the near bank to the column of the pile, with scent.
      way =
        for c <- nest_col..col//if(col >= nest_col, do: 1, else: -1),
            do: Grid.cell(world.grid, 6, c)

      world = Enum.reduce(way, world, &Sim.walk(&2, id, &1, true))

      world =
        Enum.reduce(1..6, world, fn n, world ->
          cell = Sim.river_cell(world, n, col)

          stand =
            if n == 1, do: Grid.cell(world.grid, 13, col), else: Sim.river_cell(world, n - 1, col)

          world = Sim.walk(world, id, stand, true)
          {:ok, world} = World.lock(world, id, cell)
          world
        end)

      # The player goes across to the pile, with scent.
      world = Sim.walk(world, id, hd(Grid.neighbors(world.grid, world.pile.cell)), true)
      {world, id, col}
    end

    test "the first food of a pile makes a record with names, numbers and times" do
      {world, _id, col} = colony(40)
      first_lock = world.pile.first_lock
      {world, ticks} = Sim.run_until(world, 3000, &(&1.records != []))
      assert ticks != nil

      assert [record] = world.records
      assert record.id == 1
      assert record.names == [%{name: "Ada", helper: false, bodies: 6}]
      assert record.bodies == 6
      assert record.rows == 6
      assert record.width == 6
      assert record.time == world.now
      assert record.seconds == world.now - first_lock
      assert record.food >= 1
      refute record.done

      # The bridge of the record is the bridge that the worker with food crossed.
      assert Enum.all?(1..6, &is_map_key(world.locked, Sim.river_cell(world, &1, col)))
    end

    test "the clients get the record at the first food, and again when it changes" do
      {world, _id, _col} = colony(40)
      {world, _} = World.take_events(world)

      {events, world} =
        Enum.reduce_while(1..3000, {[], world}, fn _, {_events, world} ->
          {world, events} = World.tick(world)
          if events.records == [], do: {:cont, {[], world}}, else: {:halt, {events.records, world}}
        end)

      assert [%{id: 1, first: true, names: [%{name: "Ada"}]} | _] = Enum.reverse(events)

      # Later the record has more food. The clients get it one time each second at most.
      {_world, later} =
        Enum.reduce(1..100, {world, []}, fn _, {world, later} ->
          {world, events} = World.tick(world)
          {world, later ++ events.records}
        end)

      assert length(later) in 1..10
      refute Enum.any?(later, &Map.get(&1, :first, false))
    end

    test "when the pile has 0 units, the record has the food that got to the nest" do
      {world, _id, _col} = colony(40)
      {world, ticks} = Sim.run_until(world, 6000, &match?([%{done: true}], &1.records))
      assert ticks != nil

      [record] = world.records
      # The pile lost some units between the first lock and the first food. The other
      # units are at the nest.
      assert record.food == world.food_nest
      assert record.food in 1..40
      assert world.pile.id == 2
    end

    test "a fast bridge gives more food than a slow bridge" do
      {fast, _id, _col} = colony(40)
      {fast, _} = Sim.run_until(fast, 6000, &match?([%{done: true}], &1.records))

      # The slow colony waits 15 seconds after the first lock.
      {slow, id} = World.join(World.new(Sim.straight(6, workers: 20, pile_units: 40)), "Ada")
      slow = slow |> Sim.lock!(id, Sim.river_cell(slow, 1, 10)) |> Sim.run(150)
      assert slow.pile.units == 40 - 15
      assert hd(fast.records).food > slow.pile.units
    end

    test "the count of the bodies tells how many free bodies went on them" do
      {world, _id, col} = colony(40)
      {world, _} = Sim.run_until(world, 6000, &match?([%{done: true}], &1.records))
      first = World.body(world, Sim.river_cell(world, 1, col))
      # Each unit of food crossed the bridge two times: to the pile and to the nest.
      assert first.crossings >= 2 * hd(world.records).food
    end
  end
end
