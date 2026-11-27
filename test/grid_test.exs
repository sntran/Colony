defmodule Colony.GridTest do
  @moduledoc "The grid: the lands and the rivers of plan 0003, section 4.2."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  setup_all do
    %{grid: Grid.new(Sim.cfg(), 1)}
  end

  test "the world is 60 columns wide, and land 0 is 14 rows deep", %{grid: grid} do
    assert grid.width == 60
    assert Grid.river_count(grid) == 4
    assert Grid.river_start(grid, 1) == 14

    for cell <- 0..(14 * 60 - 1) do
      assert Grid.kind(grid, cell) == :land
      assert Grid.land(grid, cell) == 0
    end

    assert Grid.land(grid, grid.nest) == 0
  end

  test "the rivers are 5 to 7, 9 to 11, 12 to 14 and 16 to 18 rows wide" do
    limits = [{5, 7}, {9, 11}, {12, 14}, {16, 18}]

    for seed <- 1..40 do
      grid = Grid.new(Sim.cfg(), seed)

      for {{low, high}, k} <- Enum.with_index(limits, 1) do
        widths = for col <- 0..59, do: Grid.river_width(grid, k, col)
        assert Enum.min(widths) == low
        assert Enum.max(widths) == high

        # The width changes by 1 row or less from one column to the next.
        for [a, b] <- Enum.chunk_every(widths, 2, 1, :discard), do: assert(abs(a - b) <= 1)
      end
    end
  end

  test "the south edge of each river is a straight line, and each river goes across the world",
       %{grid: grid} do
    for k <- 1..4, col <- 0..59 do
      start = Grid.river_start(grid, k)
      width = Grid.river_width(grid, k, col)

      # The land before the river, the cells of the river, and the land after it.
      assert Grid.kind(grid, Grid.cell(grid, start - 1, col)) == :land
      assert Grid.land(grid, Grid.cell(grid, start - 1, col)) == k - 1

      for row <- start..(start + width - 1) do
        assert Grid.river(grid, Grid.cell(grid, row, col)) == k
        assert Grid.river_row(grid, Grid.cell(grid, row, col)) == row - start + 1
      end

      assert Grid.kind(grid, Grid.cell(grid, start + width, col)) == :land
      assert Grid.land(grid, Grid.cell(grid, start + width, col)) == k
    end
  end

  test "each land after a river is 8 rows deep or more in each column" do
    for seed <- 1..10 do
      grid = Grid.new(Sim.cfg(), seed)

      for k <- 1..4, col <- 0..59 do
        first = Grid.river_start(grid, k) + Grid.river_width(grid, k, col)
        last = if k < 4, do: Grid.river_start(grid, k + 1) - 1, else: grid.rows - 1
        assert last - first + 1 >= 8
      end
    end
  end

  test "no way around: with no bridge, no body can walk from a land to the next land" do
    for seed <- 1..40 do
      world = World.new(Sim.cfg(seed: seed))
      grid = world.grid

      # One cell of each land, and all the cells that a body gets to from it on foot.
      for k <- 0..4 do
        from =
          Enum.find(
            0..(grid.count - 1),
            &(Grid.kind(grid, &1) == :land and Grid.land(grid, &1) == k)
          )

        reach = Sim.reach(world, from)
        lands = reach |> Map.keys() |> Enum.map(&Grid.land(grid, &1)) |> Enum.uniq()
        assert lands == [k], "seed #{seed}: a body walks from land #{k} to #{inspect(lands)}"

        # The body gets to each cell of its land.
        all =
          Enum.count(
            0..(grid.count - 1),
            &(Grid.kind(grid, &1) == :land and Grid.land(grid, &1) == k)
          )

        assert map_size(reach) == all
      end
    end
  end

  test "two seeds give two worlds, and one seed gives the same world each time" do
    assert Grid.rivers(Sim.cfg(), 5) == Grid.rivers(Sim.cfg(), 5)
    assert Grid.rivers(Sim.cfg(), 5) != Grid.rivers(Sim.cfg(), 6)
  end

  test "a cell touches two cells in its row, two before and two after", %{grid: grid} do
    cell = Grid.cell(grid, 5, 10)
    neighbors = Grid.neighbors(grid, cell)
    assert length(neighbors) == 6
    assert length(Grid.beside(grid, cell)) == 2
    assert length(Grid.forward(grid, cell)) == 2
    assert hd(Grid.forward(grid, cell)) == Grid.cell(grid, 6, 10)

    for other <- neighbors do
      assert Grid.distance(grid, cell, other) == 1
      {x1, z1} = Grid.center(grid, cell)
      {x2, z2} = Grid.center(grid, other)
      assert_in_delta :math.sqrt((x1 - x2) ** 2 + (z1 - z2) ** 2), 1.0, 1.0e-9
    end

    # A cell at the edge of the grid has fewer cells that touch it.
    assert length(Grid.neighbors(grid, 0)) < 6
  end

  test "a point gives the cell that contains it", %{grid: grid} do
    for cell <- [0, 59, 700, 1234, grid.count - 1] do
      {x, z} = Grid.center(grid, cell)
      assert Grid.cell_at(grid, x, z) == cell
      assert Grid.cell_at(grid, x + 0.3, z + 0.2) == cell
      assert Grid.cell_at(grid, x - 0.3, z - 0.2) == cell
    end

    assert Grid.cell_at(grid, -3.0, 0.0) == nil
    assert Grid.cell_at(grid, 0.0, 1000.0) == nil
  end

  test "each direction has one number", %{grid: grid} do
    for cell <- [Grid.cell(grid, 5, 10), Grid.cell(grid, 6, 10)] do
      directions = for other <- Grid.neighbors(grid, cell), do: Grid.direction(grid, cell, other)
      assert Enum.sort(directions) == [0, 1, 2, 3, 4, 5]
    end
  end
end
