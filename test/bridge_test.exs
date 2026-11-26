defmodule Colony.BridgeTest do
  @moduledoc "Tests 1 and 2 of the plan: the lock rule, the support rule and the fall."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, Support, World}

  @col 30

  setup do
    {world, id} = World.join(World.new(Sim.cfg()), "Tester")
    %{world: world, id: id}
  end

  test "a bridge one cell wide stops at 7 rows", %{world: world, id: id} do
    world =
      Enum.reduce(1..7, world, fn n, world -> Sim.lock!(world, id, Sim.gap_cell(world, n, @col)) end)

    supports = for n <- 1..7, do: world.supports[Sim.gap_cell(world, n, @col)]
    assert supports == [7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0]

    # No cell of row 8 can take a body.
    last = Sim.gap_cell(world, 7, @col)

    for cell <- Grid.forward(world.grid, last) do
      refute World.can_lock?(world, cell)
      world = Sim.walk(world, id, last)
      assert {{:error, _}, _} = World.lock(world, id, cell)
    end

    {_world, events} = World.take_events(world)
    refute Enum.any?(world.frontier, &(Grid.row(world.grid, &1) == world.grid.near_rows + 7))
    assert events.structure
  end

  test "a bridge two cells wide crosses 12 rows", %{world: world, id: id} do
    world =
      Enum.reduce(1..12, world, fn n, world ->
        world
        |> Sim.lock!(id, Sim.gap_cell(world, n, @col))
        |> Sim.lock!(id, Sim.gap_cell(world, n, @col + 1))
      end)

    assert map_size(world.locked) == 24
    assert Enum.all?(world.supports, fn {_cell, support} -> support > 0 end)

    # The player goes across the bridge and touches the food.
    world = Sim.walk(world, id, world.grid.food)
    assert Grid.kind(world.grid, world.players[id].cell) == :far
    assert world.players[id].touched_food
  end

  test "a body cannot lock into a cell that does not touch its cell", %{world: world, id: id} do
    assert {{:error, _}, _} = World.lock(world, id, Sim.gap_cell(world, 1, @col))
    world = Sim.walk(world, id, Grid.cell(world.grid, 13, @col))
    assert {{:error, _}, _} = World.lock(world, id, Sim.gap_cell(world, 2, @col))
    assert {:ok, world} = World.lock(world, id, Sim.gap_cell(world, 1, @col))
    # The cell is not empty now.
    world = Sim.walk(world, id, Grid.cell(world.grid, 13, @col))
    assert {{:error, _}, _} = World.lock(world, id, Sim.gap_cell(world, 1, @col))
  end

  test "a free body cannot go into the gap", %{world: world, id: id} do
    world = Sim.walk(world, id, Grid.cell(world.grid, 13, @col))
    {x, z} = Grid.center(world.grid, Sim.gap_cell(world, 1, @col))
    {world, _} = World.take_events(world)
    world = World.move(world, id, x, z, 0.0, false)
    assert world.players[id].cell == Grid.cell(world.grid, 13, @col)
    {_world, events} = World.take_events(world)
    assert [{^id, %{x: _, z: _}}] = events.you
  end

  test "a free body cannot jump across a cell where a body cannot be", %{world: world, id: id} do
    # Three bodies in a line. Without the body in the middle, there is a hole of one cell.
    world =
      Enum.reduce(1..3, world, fn n, world -> Sim.lock!(world, id, Sim.gap_cell(world, n, @col)) end)

    first = Sim.gap_cell(world, 1, @col)
    third = Sim.gap_cell(world, 3, @col)
    world = Sim.walk(world, id, first)
    # The body waits and gets all the movement that the world lets it keep.
    world = Sim.run(world, 20)

    # To the cell that does not touch: the world refuses, with and without a hole.
    {x, z} = Grid.center(world.grid, third)
    assert World.move(world, id, x, z, 0.0, false).players[id].cell == first

    # From the far edge of the first cell, the third cell is near. With a body in the
    # middle, the way is free. With a hole, the world refuses.
    {x1, z1} = Grid.center(world.grid, first)
    world = World.move(world, id, x1, z1 + 0.45, 0.0, false)
    assert_in_delta world.players[id].z, z1 + 0.45, 0.001
    world = Sim.run(world, 20)
    assert World.move(world, id, x, z - 0.45, 0.0, false).players[id].cell == third

    hole = %{world | locked: Map.delete(world.locked, Sim.gap_cell(world, 2, @col))}
    assert World.move(hole, id, x, z - 0.45, 0.0, false).players[id].cell == first
  end

  test "a player gets a new body at the nest one second after a lock", %{world: world, id: id} do
    world = Sim.lock!(world, id, Sim.gap_cell(world, 1, @col))
    assert {:dead, _} = world.players[id].state
    world = Sim.run(world, 9)
    assert {:dead, _} = world.players[id].state
    world = Sim.run(world, 1)
    assert world.players[id].state == :alive
    assert world.players[id].cell == world.grid.nest

    body = world.locked[Sim.gap_cell(world, 1, @col)]
    assert body.kind == :player
    assert body.name == "Tester"
  end

  test "when a body goes away, the bodies that lose their support fall", %{world: world, id: id} do
    world =
      Enum.reduce(1..7, world, fn n, world -> Sim.lock!(world, id, Sim.gap_cell(world, n, @col)) end)

    third = Sim.gap_cell(world, 3, @col)
    {world, _} = World.take_events(world)
    world = World.remove(world, [{third, world.locked[third]}])

    assert Enum.sort(Map.keys(world.locked)) ==
             Enum.sort([Sim.gap_cell(world, 1, @col), Sim.gap_cell(world, 2, @col)])

    {_world, events} = World.take_events(world)
    assert Enum.sort(events.fell) == Enum.sort(for n <- 4..7, do: Sim.gap_cell(world, n, @col))
  end

  test "when a body falls, the body beside it loses support and falls also", %{world: world, id: id} do
    # One column of 7 rows. A second body in row 1 gives 0.5 more to all the rows.
    # Then row 8 has two bodies: `eighth` (1.0) and `beside` (0.5).
    world =
      Enum.reduce(1..7, world, fn n, world -> Sim.lock!(world, id, Sim.gap_cell(world, n, @col)) end)

    first = Sim.gap_cell(world, 1, @col)
    seventh = Sim.gap_cell(world, 7, @col)
    eighth = Sim.gap_cell(world, 8, @col)
    extra = Sim.gap_cell(world, 1, @col + 1)
    world = world |> Sim.lock!(id, extra) |> Sim.lock!(id, eighth)

    beside =
      Enum.find(Grid.beside(world.grid, eighth), &(&1 not in Grid.neighbors(world.grid, seventh)))

    world = Sim.lock!(world, id, beside)
    assert world.supports[seventh] == 1.5
    assert world.supports[eighth] == 1.0
    assert world.supports[beside] == 0.5

    # Without the second body of row 1: `beside` gets 0 and falls. Then `eighth` is alone
    # in its row, its cost is 1.0, it gets 0 and falls also.
    {world, _} = World.take_events(world)
    world = World.remove(world, [{extra, world.locked[extra]}])
    {world, events} = World.take_events(world)

    assert Enum.sort(events.fell) == Enum.sort([eighth, beside])

    assert Enum.sort(Map.keys(world.locked)) ==
             Enum.sort(for n <- 1..7, do: Sim.gap_cell(world, n, @col))

    assert world.supports[first] == 7.0
    assert world.supports[seventh] == 1.0
  end

  test "a free body on a body that falls goes out of the world", %{world: world, id: id} do
    world =
      Enum.reduce(1..5, world, fn n, world -> Sim.lock!(world, id, Sim.gap_cell(world, n, @col)) end)

    world = Sim.walk(world, id, Sim.gap_cell(world, 5, @col))
    second = Sim.gap_cell(world, 2, @col)
    world = World.remove(world, [{second, world.locked[second]}])
    assert {:dead, _} = world.players[id].state
    world = Sim.wait_alive(world, id)
    assert world.players[id].cell == world.grid.nest
  end

  test "the fast estimate of the support is the same as the full calculation" do
    world = World.new(Sim.cfg())
    grid = world.grid
    rule = world.rule
    gap = world.p.gap_cells |> List.to_tuple()
    :rand.seed(:exsss, 7)

    # Many random structures: add a body where the estimate permits it, then compare.
    for _ <- 1..40 do
      Enum.reduce(1..120, %{}, fn _, locked ->
        supports = Support.calculate(grid, rule, locked)
        cell = elem(gap, :rand.uniform(tuple_size(gap)) - 1)

        if is_map_key(locked, cell) do
          locked
        else
          estimate = Support.support_for(grid, rule, locked, supports, cell)
          full = Support.calculate(grid, rule, Map.put(locked, cell, true))

          case estimate do
            nil -> refute is_map_key(full, cell)
            value -> assert_in_delta value, Map.fetch!(full, cell), 1.0e-9
          end

          if estimate != nil and estimate > 0, do: Map.put(locked, cell, true), else: locked
        end
      end)
    end
  end
end
