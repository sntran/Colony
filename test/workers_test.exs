defmodule Colony.WorkersTest do
  @moduledoc "Plan 0002, section 4.1: a worker never locks. It follows scent and carries food."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  # 5 minutes of world time.
  @five_minutes 3000

  test "with no player and no helper, and scent from the nest to the river, no body locks in 5 minutes" do
    for seed <- 1..3 do
      world = World.new(Sim.cfg(workers: 200, seed: seed))

      world =
        Enum.reduce(1..@five_minutes, world, fn _, world ->
          # The line of scent stays strong for all the test.
          world = Sim.scent_line(world)
          {world, events} = World.tick(world)
          assert events.locks == []
          world
        end)

      assert world.locked == %{}
      assert world.pile.units == 300
      assert world.pile.first_lock == nil
      assert map_size(world.workers) == 200

      # The workers followed the scent: many are at the river.
      at_river = Enum.count(world.workers, fn {_id, w} -> Grid.row(world.grid, w.cell) >= 11 end)
      assert at_river > 50
    end
  end

  test "workers with no scent stay near the nest" do
    world = World.new(Sim.cfg(workers: 100)) |> Sim.run(600)

    for {_id, worker} <- world.workers do
      assert Grid.nest_distance(world.grid, worker.cell) <= 6
    end
  end

  test "workers wait at the end of a bridge that has scent: they are the next bodies" do
    {world, id} = World.join(World.new(Sim.straight(8, workers: 30)), "Ada")
    col = Grid.col(world.grid, world.grid.nest)

    # The player goes from the nest to the river with scent and locks 3 bodies.
    world =
      Enum.reduce(1..3, world, fn n, world ->
        stand =
          if n == 1, do: Grid.cell(world.grid, 13, col), else: Sim.river_cell(world, n - 1, col)

        world = Sim.walk(world, id, stand, true)
        {:ok, world} = World.lock(world, id, Sim.river_cell(world, n, col))
        world
      end)

    # The player waits at the end of the bridge with scent.
    tip = Sim.river_cell(world, 3, col)
    world = Sim.walk(world, id, tip, true)

    world =
      Enum.reduce(1..150, world, fn _, world ->
        player = world.players[id]
        world |> World.move(id, player.x, player.z, 0.0, true) |> Sim.run(1)
      end)

    on_bridge = Enum.count(world.workers, fn {_id, w} -> Grid.kind(world.grid, w.cell) == :gap end)
    assert on_bridge >= 5

    # After the next lock, the new body of the player is on the bridge, not at the nest.
    assert {:ok, world} = World.lock(world, id, Sim.river_cell(world, 4, col))
    assert Grid.kind(world.grid, world.players[id].cell) == :gap
  end

  test "workers go around a corner of a bridge to the pile" do
    # A bridge that goes to the side at its end. A worker that goes only nearer to the
    # pile in a straight line stops at the corner.
    {world, id} = World.join(World.new(Sim.straight(6, workers: 20, pile_units: 30)), "Ada")
    col = world.pile.col - 3

    cells =
      for(n <- 1..4, do: Sim.river_cell(world, n, col)) ++
        for(c <- (col + 1)..(col + 3), do: Sim.river_cell(world, 4, c)) ++
        for n <- 5..6, do: Sim.river_cell(world, n, col + 3)

    world = Enum.reduce(cells, world, &Sim.lock!(&2, id, &1))
    assert Sim.way_to_pile?(Sim.run(world, 1))

    # Scent from the nest, along the bank, across the bridge and to the pile.
    nest_col = Grid.col(world.grid, world.grid.nest)
    step = if col >= nest_col, do: 1, else: -1
    bank = for c <- nest_col..col//step, do: Grid.cell(world.grid, 6, c)

    world =
      Enum.reduce(
        bank ++ [Grid.cell(world.grid, 13, col)] ++ cells,
        world,
        &Sim.walk(&2, id, &1, true)
      )

    world = Sim.walk(world, id, hd(Grid.neighbors(world.grid, world.pile.cell)), true)

    {world, ticks} = Sim.run_until(world, @five_minutes, &(&1.food_nest >= 10))
    assert ticks != nil, "the workers did not bring 10 units in 5 minutes"
    assert [%{names: [%{name: "Ada", bodies: 9}]}] = world.records
  end
end
