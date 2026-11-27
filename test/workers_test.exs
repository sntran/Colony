defmodule Colony.WorkersTest do
  @moduledoc "The two kinds of workers and the nest that moves: plan 0004, 4.1 and 4.2."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  @moduletag timeout: 300_000

  defp start(changes \\ []) do
    World.new(Sim.cfg(Keyword.merge([carriers: 12, spare: 10], changes)))
  end

  test "the colony starts with 12 carriers and 10 spare bodies near the nest" do
    world = start()
    assert World.carriers(world) == 12
    assert World.spare(world) == 10
    assert length(Sim.workers(world, :carrier)) == 12

    for {_id, worker} <- world.workers do
      assert Grid.distance(world.grid, worker.cell, world.nest) <= 3
    end
  end

  test "with no player and no helper, no body locks in 5 minutes, and the spare bodies wait at the crossing place" do
    for seed <- 1..3 do
      world = start(seed: seed)

      {world, locks} =
        Enum.reduce(1..3000, {world, 0}, fn _, {world, locks} ->
          {world, events} = World.tick(world)
          {world, locks + length(events.locks)}
        end)

      assert locks == 0
      assert world.locked == %{}
      assert World.spare(world) == 10
      assert World.carriers(world) == 12

      # Each spare body waits on a cell that touches an open cell. One is on each cell.
      cells = for {_id, worker} <- Sim.workers(world, :spare), do: worker.cell
      assert Enum.uniq(cells) == cells
      assert Enum.all?(cells, &(Map.fetch!(world.front, &1) == 0))

      # The carriers have no pile that they can walk to: they stay near the nest.
      for {_id, worker} <- Sim.workers(world, :carrier) do
        assert worker.carry == nil
        assert Grid.distance(world.grid, worker.cell, world.nest) <= world.p.leash
      end
    end
  end

  test "one body locks 6 times across river 1: food is at the nest in less than 20 seconds" do
    {world, id} = World.join(start(rivers: [{6, 6}, {9, 11}, {12, 14}, {16, 18}]), "Tester")
    world = Sim.run(world, 300)
    world = Sim.cross!(world, id, 1)
    assert length(World.bridge(world, 1)) == 6
    assert world.food_nest == 0

    {world, ticks} = Sim.run_until(world, 600, &(&1.food_nest > 0))
    assert ticks != nil
    IO.puts("\n  first food after the crossing of river 1: #{ticks / 10} s")
    assert ticks < 200
    assert Sim.way_to_pile?(world, 1)
  end

  test "a lock never uses a carrier: the nearest spare body is the new body" do
    {world, id} = World.join(start(), "Tester")
    world = Sim.run(world, 300)
    carriers = Sim.workers(world, :carrier) |> Map.new()
    [cell | _] = Sim.open(world)
    world = Sim.lock!(world, id, cell)
    assert World.carriers(world) == 12
    assert World.spare(world) == 9
    # The carriers are the same carriers.
    assert Sim.workers(world, :carrier) |> Map.new() |> Map.keys() == Map.keys(carriers)
    took = world.players[id].took
    refute is_map_key(carriers, took)
  end

  test "with no spare body, a lock is not possible, also when the colony has carriers" do
    {world, id} = World.join(start(spare: 1, spare_low: 0), "Tester")
    world = Sim.run(world, 200)
    world = Sim.lock!(world, id, hd(Sim.open(world)))
    assert World.spare(world) == 0
    assert World.carriers(world) == 12
    world = Sim.wait_ready(world, id)
    [cell | _] = Sim.open(world)
    stand = world.grid |> Grid.neighbors(cell) |> Enum.find(&World.walkable?(world, &1))
    world = Sim.walk(world, id, stand)
    assert {{:error, :not_possible}, _} = World.lock(world, id, cell)
  end

  test "a carrier brings food from the nearest pile that it can walk to, and waits near the nest with no pile" do
    {world, id} = World.join(start(), "Tester")
    world = world |> Sim.run(200) |> Sim.cross!(id, 1)
    {world, ticks} = Sim.run_until(world, 600, &(&1.food_nest >= 12))
    assert ticks != nil
    # Only carriers carry food. A spare body never carries food.
    {world, _} = Sim.run_until(world, 50, fn _ -> false end)

    for {_id, worker} <- Sim.workers(world, :spare), do: assert(worker.carry == nil)
    assert Enum.any?(Sim.workers(world, :carrier), fn {_id, worker} -> is_integer(worker.carry) end)
  end

  describe "the nest makes spare bodies" do
    test "5 units of food at the nest make one spare body, at the nest" do
      world = start(spare: 0, carriers: 0)
      world = Enum.reduce(1..4, world, fn _, world -> World.add_nest_food(world, 1, 1) end)
      assert World.spare(world) == 0
      world = World.add_nest_food(world, 1, 1)
      assert World.spare(world) == 1
      assert [{_id, %{cell: cell, kind: :spare}}] = Map.to_list(world.workers)
      assert cell == world.nest
      # Food never makes a carrier.
      world = World.add_nest_food(world, 1, 50)
      assert World.spare(world) == 11
      assert World.carriers(world) == 0
    end

    test "the colony has 200 spare bodies and 150 carriers at most" do
      world = start(spare: 199, carriers: 0)
      world = World.add_nest_food(world, 1, 50)
      assert World.spare(world) == 200
    end

    test "with fewer than 5 spare bodies and no pile that a body can walk to, the nest makes one each 10 seconds" do
      world = start(spare: 2, carriers: 0)
      assert World.food_piles(world) == []
      world = Sim.run(world, 100)
      assert World.spare(world) == 3
      world = Sim.run(world, 200)
      assert World.spare(world) == 5
      world = Sim.run(world, 300)
      assert World.spare(world) == 5
    end

    test "with a pile that a body can walk to, the nest makes no spare body with no food" do
      cfg = [spare: 6, carriers: 0, carriers_per_crossing: 0, rivers: [{5, 5}, {9, 9}]]
      {world, id} = World.join(start(cfg), "Tester")
      world = Sim.cross!(world, id, 1)
      assert World.spare(world) == 1
      assert World.food_piles(world) != []
      world = Sim.run(world, 300)
      assert World.spare(world) == 1
    end
  end

  describe "the nest follows the colony" do
    test "at each crossing the nest moves to the foot of the new bridge, and the old nest stays as a mark" do
      {world, id} = World.join(start(carriers: 0, spare: 60), "Tester")
      grid = world.grid
      start_nest = world.nest

      world =
        Enum.reduce(1..3, world, fn k, world ->
          before = world.nest
          world = Sim.cross!(world, id, k)
          # The first body of the bridge, and 3 rows south of it.
          {first, _} =
            world.locked
            |> Enum.filter(fn {c, _} -> Grid.river(grid, c) == k end)
            |> Enum.min_by(fn {_, b} -> b.n end)

          assert world.nest == Grid.cell(grid, Grid.row(grid, first) - 3, Grid.col(grid, first))
          assert Grid.land(grid, world.nest) == k - 1 and Grid.kind(grid, world.nest) == :land
          assert hd(world.old_nests) == %{cell: before, land: Grid.land(grid, before)}
          world
        end)

      assert length(world.old_nests) == 3
      assert List.last(world.old_nests).cell == start_nest
      # The colony got 8 carriers at each crossing.
      assert World.carriers(world) == 24
    end

    test "the carriers and the spare bodies get to the new place, and the carriers carry eggs" do
      {world, id} = World.join(start(carriers: 12, spare: 40), "Tester")
      world = world |> Sim.run(300) |> Sim.cross!(id, 1)
      world = Sim.run(world, 600)
      world = Sim.cross!(world, id, 2)
      new_nest = world.nest
      eggs = Enum.count(Sim.workers(world, :carrier), fn {_id, w} -> w.mode == {:egg, :fetch} end)
      assert eggs > 0

      # The carriers take eggs from the old nest to the new nest.
      {world, seen} =
        Enum.reduce(1..600, {world, 0}, fn _, {world, seen} ->
          {world, events} = World.tick(world)

          {world,
           seen +
             Enum.count(events.worker_set, fn {_id, _cell, flags} -> Bitwise.band(flags, 4) != 0 end)}
        end)

      assert seen >= eggs
      assert world.to_old_nest == %{}

      # After the eggs, no carrier carries an egg, and the carriers bring food to the new nest.
      for {_id, worker} <- Sim.workers(world, :carrier), do: assert(worker.carry != :egg)
      assert world.nest == new_nest

      # The spare bodies wait at the crossing place of river 3: a crowd, one on each cell.
      cells = for {_id, worker} <- Sim.workers(world, :spare), do: worker.cell
      assert Enum.uniq(cells) == cells
      # The nest makes new spare bodies all the time: a few are on their way.
      near =
        Enum.count(
          cells,
          &(Grid.kind(world.grid, &1) == :land and Grid.land(world.grid, &1) == 2 and
              Map.fetch!(world.front, &1) <= 15)
        )

      assert near >= length(cells) * 0.9
      # The cells at the crossing place have a spare body first.
      place = for {cell, 0} <- world.front, do: cell
      assert Enum.all?(place, &(&1 in cells))
    end

    test "a player with food can bring it to the new nest" do
      {world, one} =
        World.join(start(carriers: 0, spare: 40, rivers: [{5, 5}, {9, 9}, {9, 9}]), "One")

      {world, two} = World.join(world, "Two")
      world = Sim.cross!(world, one, 1)
      # Two takes food at pile 1. Then One makes the crossing of river 2: the nest moves.
      world = Sim.walk(world, two, world.piles[1].cell)
      world = Sim.run(world, 1)
      assert world.players[two].carry.units == 10
      old = world.nest
      world = Sim.cross!(world, one, 2)
      assert world.nest != old
      food = world.food_nest
      world = Sim.walk(world, two, world.nest)
      world = Sim.run(world, 1)
      assert world.players[two].carry == nil
      assert world.food_nest == food + 10
    end
  end

  test "twenty bodies lock as fast as the rules permit for 5 minutes: the carriers never decrease and food comes all the time" do
    world =
      World.new(Sim.cfg(carriers: 12, spare: 10, helpers: 20, helper_lock_seconds: 0, seed: 4))

    # Food comes all the time: while a pile with food is there, the time with no new food at
    # the nest is not longer than one trip from the nest to the farthest pile with food and
    # back, and 5 seconds. A carrier goes to the pile that is nearest to it, thus a carrier
    # can be on such a trip. After a crossing of a wide river, a trip is long.
    {world, stats} =
      Enum.reduce(
        1..3000,
        {world, %{carriers: 12, locks: 0, last_food: nil, gap: 0, over: 0, food: 0}},
        fn _, {world, stats} ->
          {world, events} = World.tick(world)
          carriers = World.carriers(world)
          assert carriers >= stats.carriers, "the carriers decreased at tick #{world.tick}"

          stats =
            case World.food_piles(world) do
              _ when world.food_nest > stats.food ->
                %{stats | last_food: world.tick, food: world.food_nest}

              [_ | _] = piles when stats.last_food != nil ->
                steps = piles |> Enum.map(&Map.fetch!(world.walk, &1.cell)) |> Enum.max()
                trip = round(2 * steps / world.p.step) + 50
                gap = world.tick - stats.last_food
                %{stats | gap: max(stats.gap, gap), over: max(stats.over, gap - trip)}

              _ ->
                %{stats | last_food: stats.last_food && world.tick}
            end

          {world, %{stats | carriers: carriers, locks: stats.locks + length(events.locks)}}
        end
      )

    IO.puts(
      "\n  20 fast bodies, 5 minutes: #{stats.locks} locks, #{world.stage - 1} crossings, " <>
        "#{World.carriers(world)} carriers, #{World.spare(world)} spare bodies, #{world.food_nest} food, " <>
        "the longest time with no food: #{stats.gap / 10} s"
    )

    assert stats.locks > 30
    assert world.food_nest > 100
    assert stats.over <= 0, "#{stats.over / 10} s more than a trip with no food"
  end
end
