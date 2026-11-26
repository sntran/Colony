defmodule Colony.GridTest do
  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim}

  setup_all do
    %{grid: Grid.new(Sim.cfg(), 1)}
  end

  test "the grid has a near bank of 14 rows and 60 columns", %{grid: grid} do
    assert grid.width == 60
    assert grid.near_rows == 14
    assert Grid.kind(grid, grid.nest) == :near
    assert Enum.all?(0..59, &(Grid.kind(grid, Grid.cell(grid, 13, &1)) == :near))
    assert Enum.all?(0..59, &(Grid.kind(grid, Grid.cell(grid, 14, &1)) == :gap))
  end

  test "the river is 5 to 16 rows wide, and its narrowest place is near the nest" do
    for seed <- 1..40 do
      cfg = Sim.cfg()
      river = Grid.river(cfg, seed)
      {_row, nest_col} = cfg[:nest]
      {narrow, widest} = Enum.min_max(river)

      assert length(river) == 60
      assert narrow in [5, 6], "seed #{seed}: the narrowest place is #{narrow} rows"
      assert widest == 16
      place = Enum.find_index(river, &(&1 == narrow))
      assert abs(place - nest_col) <= 6, "seed #{seed}: the narrowest place is at column #{place}"

      # Each width of the sequence of the piles is somewhere.
      for width <- cfg[:pile_widths], do: assert(width in river)

      # The edge of the far bank has no large step.
      for [a, b] <- Enum.chunk_every(river, 2, 1, :discard), do: assert(abs(a - b) <= 2)
    end
  end

  test "two seeds give two rivers, and one seed gives the same river each time" do
    cfg = Sim.cfg()
    rivers = for seed <- 1..10, do: Grid.river(cfg, seed)
    assert length(Enum.uniq(rivers)) >= 8
    assert Grid.river(cfg, 7) == Grid.river(cfg, 7)
  end

  test "the far bank starts after the river in each column", %{grid: grid} do
    for col <- 0..59 do
      width = Grid.river_width(grid, col)
      assert Grid.kind(grid, Grid.cell(grid, 14 + width - 1, col)) == :gap
      assert Grid.kind(grid, Grid.cell(grid, 14 + width, col)) == :far
      assert Grid.river_row(grid, Grid.cell(grid, 14 + width - 1, col)) == width
    end
  end

  test "a cell touches two cells in its row, two before and two after", %{grid: grid} do
    for row <- [5, 6, 20, 21], col <- [1, 30, 58] do
      cell = Grid.cell(grid, row, col)
      rows = grid |> Grid.neighbors(cell) |> Enum.map(&(Grid.row(grid, &1) - row)) |> Enum.sort()
      assert rows == [-1, -1, 0, 0, 1, 1]
      assert length(Grid.forward(grid, cell)) == 2
      assert length(Grid.beside(grid, cell)) == 2
      # The first cell of `forward` is in the same column.
      assert Grid.col(grid, hd(Grid.forward(grid, cell))) == col

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
