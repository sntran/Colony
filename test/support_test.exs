defmodule Colony.SupportTest do
  @moduledoc "The support rule. Plan 0003 does not change it: 96 for the land, costs 12, 6, 4 and 3."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, Support, World}

  @col 30

  # One river of 26 rows with the same width in all its columns.
  setup_all do
    %{world: World.new(Sim.straight(26))}
  end

  # Bodies in the rows 1 to `rows` of the river, `wide` bodies in each row.
  defp block(world, rows, wide) do
    for row <- 1..rows, col <- @col..(@col + wide - 1), into: %{} do
      {Sim.river_cell(world, row, col), true}
    end
  end

  describe "the integers of the rule" do
    test "the land support is 96 and the costs are 12, 6, 4 and 3", %{world: world} do
      assert world.rule.bank == 96
      assert world.rule.costs == {12, 6, 4, 3}
    end

    test "the cost of a body comes from the bodies in its line, 4 at most", %{world: world} do
      grid = world.grid
      rule = world.rule

      for {wide, cost} <- [{1, 12}, {2, 6}, {3, 4}, {4, 3}, {5, 3}, {9, 3}] do
        locked = block(world, 1, wide)
        for {cell, _} <- locked, do: assert(Support.cost(grid, rule, locked, cell) == cost)
      end

      # A hole divides a line.
      locked = Map.delete(block(world, 1, 5), Sim.river_cell(world, 1, @col + 2))
      assert Support.cost(grid, rule, locked, Sim.river_cell(world, 1, @col)) == 6
    end
  end

  describe "how far a bridge goes with the support of one land" do
    for {wide, rows} <- [{1, 7}, {2, 15}, {3, 23}] do
      test "a bridge #{wide} wide stops at #{rows} rows", %{world: world} do
        wide = unquote(wide)
        rows = unquote(rows)
        grid = world.grid
        rule = world.rule

        # Each body of the last row has support, and it is the support of one cost or less.
        locked = block(world, rows, wide)
        supports = Support.calculate(grid, rule, locked)
        assert map_size(supports) == rows * wide
        assert Enum.all?(supports, fn {_cell, support} -> support > 0 end)

        # No body can lock in the next row.
        for col <- (@col - 1)..(@col + wide) do
          refute Support.can_lock?(grid, rule, locked, Sim.river_cell(world, rows + 1, col))
        end
      end
    end

    test "a bridge gets support from the land on each side" do
      # A river of 8 rows: a bridge one body wide goes to row 7 from the south, and the
      # body in row 8 gets its support from the north.
      world = World.new(Sim.straight(8))
      locked = block(world, 7, 1)
      last = Sim.river_cell(world, 8, @col)
      assert Support.can_lock?(world.grid, world.rule, locked, last)
      assert Support.support_for(world.grid, world.rule, locked, last) == 96 - 12
    end
  end

  describe "the calculation with integers" do
    # A full calculation with fractions: the land support is 8 and the cost is 1 / n.
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

    defp small do
      world = World.new(Sim.straight(9, width: 8, nest: {6, 4}))
      grid = world.grid
      cells = for cell <- 0..(grid.count - 1), Grid.kind(grid, cell) == :gap, do: cell
      {grid, world.rule, cells}
    end

    test "gives the same result as a full calculation with fractions" do
      {grid, rule, cells} = small()
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

    test "a lock has support exactly when the full calculation gives support" do
      {grid, rule, cells} = small()
      :rand.seed(:exsss, 5)

      for _ <- 1..15 do
        # A structure that grows by locks that the support rule permits.
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
      {grid, rule, cells} = small()
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
end
