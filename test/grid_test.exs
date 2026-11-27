defmodule Colony.GridTest do
  @moduledoc """
  The grid: the lands and the rivers. Plan 0003, section 4.2, and plan 0004, section 4.9:
  the world has no end.
  """

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  # The widths of the config: river 7 and each river after it are 25 to 27 rows wide.
  @limits [{5, 7}, {9, 11}, {12, 14}, {16, 18}, {19, 21}, {22, 24}, {25, 27}]
  @rivers 20

  setup_all do
    grids =
      1..20
      |> Task.async_stream(&{&1, Grid.new(Sim.cfg(), &1, @rivers)}, timeout: :infinity)
      |> Enum.map(fn {:ok, entry} -> entry end)

    %{grid: Grid.new(Sim.cfg(), 1), grids: grids}
  end

  defp limits(k), do: Enum.at(@limits, min(k, length(@limits)) - 1)

  test "the world is 60 columns wide, and land 0 is 14 rows deep", %{grid: grid} do
    assert grid.width == 60
    # Pile 1 is on land 1. The world has two rivers after it.
    assert Grid.river_count(grid) == 3
    assert Grid.river_start(grid, 1) == 14

    for cell <- 0..(14 * 60 - 1) do
      assert Grid.kind(grid, cell) == :land
      assert Grid.land(grid, cell) == 0
    end

    assert Grid.land(grid, grid.nest) == 0
  end

  describe "for 20 seeds and 20 rivers (automatic test 7)" do
    test "the widths of the rivers are the widths of the table", %{grids: grids} do
      for {seed, grid} <- grids, k <- 1..@rivers do
        {low, high} = limits(k)
        widths = for col <- 0..59, do: Grid.river_width(grid, k, col)
        assert Enum.min(widths) == low, "seed #{seed}, river #{k}"
        assert Enum.max(widths) == high, "seed #{seed}, river #{k}"
        assert high <= 27
        # The table has a number for each width.
        for width <- widths, do: assert(Map.has_key?(Sim.cfg()[:bridge_best], width))

        # The width changes by 1 row or less from one column to the next.
        for [a, b] <- Enum.chunk_every(widths, 2, 1, :discard), do: assert(abs(a - b) <= 1)
      end
    end

    test "the south edge of each river is a straight line, each river goes across the world, and each land is 8 rows deep or more",
         %{grids: grids} do
      for {_seed, grid} <- grids, k <- 1..@rivers, col <- 0..59 do
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

        last = if k < @rivers, do: Grid.river_start(grid, k + 1) - 1, else: grid.rows - 1
        assert last - (start + width) + 1 >= 8
      end
    end

    test "no way around: with no bridge, no body can walk from a land to the next land",
         %{grids: grids} do
      for {seed, grid} <- grids do
        world = %{World.new(Sim.cfg(seed: seed)) | grid: grid}

        # One cell of each land, and all the cells that a body gets to from it on foot.
        by_land =
          0..(grid.count - 1)
          |> Enum.filter(&(Grid.kind(grid, &1) == :land))
          |> Enum.group_by(&Grid.land(grid, &1))

        for k <- 0..@rivers do
          cells = Map.fetch!(by_land, k)
          reach = Sim.reach(world, hd(cells))
          lands = reach |> Map.keys() |> Enum.map(&Grid.land(grid, &1)) |> Enum.uniq()
          assert lands == [k], "seed #{seed}: a body walks from land #{k} to #{inspect(lands)}"
          # The body gets to each cell of its land.
          assert map_size(reach) == length(cells)
        end
      end
    end

    test "each river has a pile after it and a start of a bridge before it", %{grids: grids} do
      for {seed, grid} <- grids do
        world = %{World.new(Sim.cfg(seed: seed)) | grid: grid}

        Enum.reduce(1..@rivers, nil, fn k, before ->
          col = World.pile_column(world, k, before)
          cell = World.pile_cell(world, k, col)

          # Pile k is a land cell of land k, 10 columns or more from each edge (pile 1:
          # 10 columns or less from the nest), and 12 columns or less from pile k - 1.
          assert Grid.kind(grid, cell) == :land and Grid.land(grid, cell) == k
          assert Grid.row(grid, cell) < grid.rows

          if before do
            assert abs(col - before) <= 12
            assert col in 10..49
          else
            assert abs(col - Grid.col(grid, grid.nest)) <= 10
          end

          # The first body of bridge k locks into a cell of the first row of river k, 6
          # columns or less from the column of pile k. A body stands on land k - 1 below
          # each of these cells.
          start =
            for c <- (col - 6)..(col + 6),
                c in 0..59,
                do: Grid.cell(grid, Grid.river_start(grid, k), c)

          assert length(start) == 13

          for cell <- start do
            assert Grid.river(grid, cell) == k and Grid.river_row(grid, cell) == 1

            assert Enum.any?(
                     Grid.neighbors(grid, cell),
                     &(Grid.kind(grid, &1) == :land and Grid.land(grid, &1) == k - 1)
                   )
          end

          col
        end)
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
