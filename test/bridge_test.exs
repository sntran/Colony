defmodule Colony.BridgeTest do
  @moduledoc "The lock rule and the support rule of plan 0002: each body beside a body helps."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, Support, World}

  @col 30

  # A river of 26 rows with the same width in all its columns.
  setup do
    {world, id} = World.join(World.new(Sim.straight(26)), "Tester")
    %{world: world, id: id}
  end

  # Bodies in the rows 1 to `rows` of the river, `wide` bodies in each row.
  defp block(world, rows, wide) do
    for row <- 1..rows, col <- @col..(@col + wide - 1), into: %{} do
      {Sim.river_cell(world, row, col), true}
    end
  end

  describe "the integers of the rule" do
    test "the bank support is 96 and the costs are 12, 6, 4 and 3", %{world: world} do
      assert world.rule.bank == 96
      assert world.rule.costs == {12, 6, 4, 3}
    end

    test "the cost of a body comes from the bodies in its line, 4 at most", %{world: world} do
      grid = world.grid
      rule = world.rule
      cell = &Sim.river_cell(world, 3, &1)

      line = fn cols -> Map.new(cols, &{cell.(&1), true}) end
      assert Support.cost(grid, rule, line.([30]), cell.(30)) == 12
      assert Support.cost(grid, rule, line.([30, 31]), cell.(30)) == 6
      assert Support.cost(grid, rule, line.([30, 31, 32]), cell.(31)) == 4
      assert Support.cost(grid, rule, line.([30, 31, 32, 33]), cell.(33)) == 3
      assert Support.cost(grid, rule, line.([30, 31, 32, 33, 34, 35]), cell.(32)) == 3
      # A hole stops the line.
      assert Support.cost(grid, rule, line.([30, 31, 33, 34, 35]), cell.(31)) == 6
      assert Support.cost(grid, rule, line.([30, 31, 33, 34, 35]), cell.(34)) == 4
    end
  end

  describe "how far a bridge goes" do
    for {wide, rows} <- [{1, 7}, {2, 15}, {3, 23}] do
      test "a bridge #{wide} bodies wide stops at #{rows} rows", %{world: world} do
        wide = unquote(wide)
        rows = unquote(rows)
        grid = world.grid
        rule = world.rule

        # All the bodies of the rows 1 to `rows` have support.
        locked = block(world, rows, wide)
        supports = Support.calculate(grid, rule, locked)
        assert map_size(supports) == rows * wide
        assert Enum.all?(supports, fn {_cell, support} -> support > 0 end)
        assert supports[Sim.river_cell(world, rows, @col)] == 96 - rows * div(12, wide)

        # No body of the next row has support: not one body, and not a full row.
        for col <- (@col - 1)..(@col + wide) do
          refute Support.can_lock?(grid, rule, locked, Sim.river_cell(world, rows + 1, col))
        end

        {supports, fallen} = Support.settle(grid, rule, block(world, rows + 1, wide))
        assert length(fallen) == wide
        assert map_size(supports) == rows * wide
      end
    end

    test "a player builds one body wide to row 7, and cannot lock in row 8", %{world: world, id: id} do
      world =
        Enum.reduce(1..7, world, fn n, world ->
          Sim.lock!(world, id, Sim.river_cell(world, n, @col))
        end)

      supports = for n <- 1..7, do: world.supports[Sim.river_cell(world, n, @col)]
      assert supports == [84, 72, 60, 48, 36, 24, 12]

      last = Sim.river_cell(world, 7, @col)
      world = Sim.walk(world, id, last)

      for cell <- Grid.forward(world.grid, last) do
        refute World.can_lock?(world, cell)
        assert {{:error, _}, _} = World.lock(world, id, cell)
      end

      # A body beside the last body gives the bridge one row more.
      beside = hd(Grid.beside(world.grid, last))
      assert {:ok, world} = World.lock(world, id, beside)
      assert world.supports[last] == 18
      assert World.can_lock?(world, hd(Grid.forward(world.grid, last)))
    end

    test "the reach tells how far a bridge can grow", %{world: world} do
      grid = world.grid
      rule = world.rule
      one = block(world, 3, 1)
      assert Support.reach(grid, rule, one, Support.calculate(grid, rule, one)) == {7, false}

      # With a body beside the body of row 3, all the later rows get 6 more: one row more.
      cell = Sim.river_cell(world, 3, @col + 1)
      supports = Support.with_body(grid, rule, one, cell)
      assert supports[cell] == 66
      assert Support.reach(grid, rule, Map.put(one, cell, true), supports) == {8, false}
    end

    test "the reach tells that a bridge gets to the far bank" do
      world = World.new(Sim.straight(6))
      locked = block(world, 2, 1)

      assert Support.reach(
               world.grid,
               world.rule,
               locked,
               Support.calculate(world.grid, world.rule, locked)
             ) ==
               {6, true}
    end
  end

  describe "the calculation with integers" do
    # A full calculation with fractions: the bank support is 8 and the cost is 1 / n.
    # A fraction is {numerator, denominator}.
    defp minus({a, b}, {c, d}), do: reduce({a * d - c * b, b * d})
    defp reduce({a, b}), do: {div(a, Integer.gcd(a, b)), div(b, Integer.gcd(a, b))}
    defp more?({a, b}, {c, d}), do: a * d > c * b

    defp full(grid, locked) do
      zero = Map.new(locked, fn {cell, _} -> {cell, {0, 1}} end)
      rounds(grid, locked, zero)
    end

    defp rounds(grid, locked, supports) do
      next =
        Map.new(locked, fn {cell, _} ->
          cost = {1, min(Support.line(grid, locked, cell), 4)}

          sources =
            for n <- Grid.neighbors(grid, cell),
                Grid.kind(grid, n) != :gap or is_map_key(locked, n) do
              if Grid.kind(grid, n) != :gap, do: {8, 1}, else: Map.fetch!(supports, n)
            end

          best =
            Enum.reduce(sources, {0, 1}, fn s, best -> if more?(s, best), do: s, else: best end)

          value = minus(best, cost)
          {cell, if(more?(value, {0, 1}), do: value, else: {0, 1})}
        end)

      if next == supports, do: supports, else: rounds(grid, locked, next)
    end

    test "gives the same result as a full calculation with fractions" do
      world = World.new(Sim.straight(9, width: 8))
      grid = world.grid
      rule = world.rule
      cells = for cell <- 0..(grid.count - 1), Grid.kind(grid, cell) == :gap, do: cell
      :rand.seed(:exsss, 11)

      # Many random structures. Some bodies in them have no support.
      for _ <- 1..60 do
        locked = cells |> Enum.take_random(:rand.uniform(50)) |> Map.new(&{&1, true})
        integers = Support.calculate(grid, rule, locked)
        fractions = full(grid, locked)

        for {cell, {a, b}} <- fractions do
          # Twelfths are exact: 12 * a / b is an integer.
          assert rem(12 * a, b) == 0
          assert max(Map.get(integers, cell, 0), 0) == div(12 * a, b)
        end
      end
    end

    test "a lock is possible exactly when the full calculation gives support" do
      world = World.new(Sim.straight(9, width: 8))
      grid = world.grid
      rule = world.rule
      cells = for cell <- 0..(grid.count - 1), Grid.kind(grid, cell) == :gap, do: cell
      :rand.seed(:exsss, 5)

      for _ <- 1..15 do
        # A structure that grows by locks that the rule permits.
        locked =
          Enum.reduce(1..40, %{}, fn _, locked ->
            cell = Enum.random(cells)

            if Support.can_lock?(grid, rule, locked, cell),
              do: Map.put(locked, cell, true),
              else: locked
          end)

        assert Support.settle(grid, rule, locked) |> elem(1) == []

        for cell <- cells, not is_map_key(locked, cell) do
          {_a, b} = value = Map.fetch!(full(grid, Map.put(locked, cell, true)), cell)
          assert b > 0
          assert Support.can_lock?(grid, rule, locked, cell) == more?(value, {0, 1})
        end
      end
    end

    test "a new body never decreases the support of a body" do
      world = World.new(Sim.straight(9, width: 8))
      grid = world.grid
      rule = world.rule
      cells = for cell <- 0..(grid.count - 1), Grid.kind(grid, cell) == :gap, do: cell
      :rand.seed(:exsss, 9)

      Enum.reduce(1..150, %{}, fn _, locked ->
        cell = Enum.random(cells)

        if Support.can_lock?(grid, rule, locked, cell) do
          before = Support.calculate(grid, rule, locked)
          next = Support.calculate(grid, rule, Map.put(locked, cell, true))
          for {body, support} <- before, do: assert(next[body] >= support)
          Map.put(locked, cell, true)
        else
          locked
        end
      end)
    end
  end

  describe "the lock rule" do
    test "a body cannot lock into a cell that does not touch its cell", %{world: world, id: id} do
      assert {{:error, _}, _} = World.lock(world, id, Sim.river_cell(world, 1, @col))
      world = Sim.walk(world, id, Grid.cell(world.grid, 13, @col))
      assert {{:error, _}, _} = World.lock(world, id, Sim.river_cell(world, 2, @col))
      assert {:ok, world} = World.lock(world, id, Sim.river_cell(world, 1, @col))
      # The cell is not empty now.
      world = Sim.walk(world, id, Grid.cell(world.grid, 13, @col))
      assert {{:error, _}, _} = World.lock(world, id, Sim.river_cell(world, 1, @col))
    end

    test "a free body cannot go into the river", %{world: world, id: id} do
      world = Sim.walk(world, id, Grid.cell(world.grid, 13, @col))
      {x, z} = Grid.center(world.grid, Sim.river_cell(world, 1, @col))
      {world, _} = World.take_events(world)
      world = World.move(world, id, x, z, 0.0, false)
      assert world.players[id].cell == Grid.cell(world.grid, 13, @col)
      {_world, events} = World.take_events(world)
      assert [{^id, %{x: _, z: _}}] = events.you
    end

    test "a free body cannot jump across a cell where a body cannot be", %{world: world, id: id} do
      # Three bodies in a line. Without the body in the middle, there is a hole of one cell.
      world =
        Enum.reduce(1..3, world, fn n, world ->
          Sim.lock!(world, id, Sim.river_cell(world, n, @col))
        end)

      first = Sim.river_cell(world, 1, @col)
      third = Sim.river_cell(world, 3, @col)
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

      hole = %{world | locked: Map.delete(world.locked, Sim.river_cell(world, 2, @col))}
      assert World.move(hole, id, x, z - 0.45, 0.0, false).players[id].cell == first
    end

    test "a locked body stays: no rule removes it", %{world: world, id: id} do
      world =
        Enum.reduce(1..4, world, fn n, world ->
          Sim.lock!(world, id, Sim.river_cell(world, n, @col))
        end)

      bodies = Map.keys(world.locked)
      world = world |> World.leave(id) |> Sim.run(3000)
      assert Map.keys(world.locked) == bodies
    end
  end
end
