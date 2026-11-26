defmodule Colony.GridTest do
  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim}

  setup_all do
    %{grid: Grid.new(Sim.cfg())}
  end

  test "the grid has the size of the plan", %{grid: grid} do
    assert grid.width == 60
    assert {grid.near_rows, grid.gap_rows, grid.far_rows} == {14, 12, 14}
    assert Grid.kind(grid, grid.nest) == :near
    assert Grid.kind(grid, grid.food) == :far
    # The food is 4 rows from the gap.
    assert Grid.row(grid, grid.food) == grid.near_rows + grid.gap_rows + 3
  end

  test "a cell touches two cells in its row, two before and two after", %{grid: grid} do
    for row <- [5, 6, 20, 21], col <- [1, 30, 58] do
      cell = Grid.cell(grid, row, col)
      rows = grid |> Grid.neighbors(cell) |> Enum.map(&(Grid.row(grid, &1) - row)) |> Enum.sort()
      assert rows == [-1, -1, 0, 0, 1, 1]
      assert length(Grid.forward(grid, cell)) == 2
      assert length(Grid.beside(grid, cell)) == 2

      for next <- Grid.neighbors(grid, cell) do
        {x1, z1} = Grid.center(grid, cell)
        {x2, z2} = Grid.center(grid, next)
        assert_in_delta :math.sqrt((x1 - x2) ** 2 + (z1 - z2) ** 2), 1.0, 1.0e-9
        assert Grid.distance(grid, cell, next) == 1
        assert cell in Grid.neighbors(grid, next)
      end
    end
  end

  test "a point gives the cell that contains it", %{grid: grid} do
    for cell <- 0..(grid.count - 1) do
      {x, z} = Grid.center(grid, cell)
      assert Grid.cell_at(grid, x, z) == cell
      assert Grid.cell_at(grid, x + 0.3, z + 0.2) == cell
      assert Grid.cell_at(grid, x - 0.45, z) == cell
    end

    assert Grid.cell_at(grid, -3.0, 2.0) == nil
    assert Grid.cell_at(grid, 10.0, 99.0) == nil
  end

  test "each direction has one number", %{grid: grid} do
    for row <- [6, 7] do
      cell = Grid.cell(grid, row, 20)
      directions = for next <- Grid.neighbors(grid, cell), do: Grid.direction(grid, cell, next)
      assert Enum.sort(directions) == [0, 1, 2, 3, 4, 5]
    end
  end
end
