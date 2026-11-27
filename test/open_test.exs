defmodule Colony.OpenTest do
  @moduledoc "The open cells: a lock is possible only where it helps. Plan 0003, section 4.5."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, Support, Table, World}

  @moduletag timeout: 300_000

  # "Best" of the table of plan 0003, for the widths 5 to 14.
  @best [5, 6, 7, 8, 10, 13, 16, 19, 22, 25]

  defp world(rows, changes \\ []),
    do: World.new(Sim.straight(rows, Keyword.merge([spare: 60], changes)))

  # The cells that are open after the locks into `cells`, in this order.
  defp open_after(world, cells) do
    locked = Map.new(cells, &{&1, true})
    start = Sim.open(world)
    Enum.sort(Support.open(world.grid, world.rule, locked, 1, start))
  end

  describe "the rule" do
    test "with no body, the first row is open, 6 columns or less from the column of the pile" do
      world = world(6)
      col = world.piles[1].col

      assert Sim.open(world) ==
               for(c <- (col - 6)..(col + 6), do: Sim.river_cell(world, 1, c))
    end

    test "after the first lock, only cells that touch the bridge are open: one bridge" do
      world = world(6)
      first = Sim.river_cell(world, 1, world.piles[1].col)
      open = open_after(world, [first])
      assert open == Enum.sort(Grid.forward(world.grid, first))
      # The other cells of the first row are not open now.
      refute Sim.river_cell(world, 1, world.piles[1].col + 3) in open
    end

    test "forward first: while a lock is possible in the next row, no cell beside is open" do
      world = world(12)
      col = world.piles[1].col
      # A bridge one body wide, in a straight line. It has support for 7 rows.
      line = for row <- 1..7, do: Sim.river_cell(world, row, col)

      for rows <- 1..6 do
        bodies = Enum.take(line, rows)
        top = List.last(bodies)
        assert open_after(world, bodies) == Enum.sort(Grid.forward(world.grid, top))
      end
    end

    test "wider only when the bridge cannot go forward" do
      world = world(12)
      grid = world.grid
      col = world.piles[1].col
      line = for row <- 1..7, do: Sim.river_cell(world, row, col)
      open = open_after(world, line)

      # No open cell is in row 8: a body there has no support.
      assert Enum.all?(open, &(Grid.river_row(grid, &1) <= 7))
      # Each cell beside a body of the bridge is open: it makes the cost of that row
      # lower, and thus the support of the top row larger.
      beside = for cell <- line, next <- Grid.beside(grid, cell), do: next
      assert Enum.all?(beside, &(&1 in open))

      # After one body beside, the bridge goes forward again.
      wide = line ++ [Sim.river_cell(world, 1, col + 1)]
      assert open_after(world, wide) == Enum.sort(Grid.forward(grid, List.last(line)))
    end

    test "an open cell always makes the highest support of the top row larger" do
      world = world(12)
      grid = world.grid
      rule = world.rule
      :rand.seed(:exsss, 3)

      Enum.reduce_while(1..80, %{}, fn _, locked ->
        case Support.open(grid, rule, locked, 1, Sim.open(world)) do
          [] ->
            {:halt, locked}

          open ->
            cell = Enum.random(open)
            assert Support.can_lock?(grid, rule, locked, cell)
            next = Map.put(locked, cell, true)

            if locked != %{} do
              top = locked |> Map.keys() |> Enum.map(&Grid.row(grid, &1)) |> Enum.max()

              if Grid.row(grid, cell) <= top do
                before = Support.top_support(grid, Support.calculate(grid, rule, locked), top)
                now = Support.top_support(grid, Support.calculate(grid, rule, next), top)
                assert now > before
              end
            end

            {:cont, next}
        end
      end)
    end

    test "a complete bridge takes no more bodies" do
      world = world(5)
      {world, id} = World.join(world, "Tester")
      world = Sim.cross!(world, id, 1)
      assert World.complete?(world, 1)
      # The open cells are in the next river only.
      assert Enum.all?(Map.keys(world.open), &(Grid.river(world.grid, &1) == 2))
      assert length(World.bridge(world, 1)) == 5

      # A cell beside the bridge has support, but it is not open.
      [body | _] = World.bridge(world, 1)
      [beside | _] = Enum.reject(Grid.beside(world.grid, body), &is_map_key(world.locked, &1))
      assert Support.can_lock?(world.grid, world.rule, world.locked, beside)
      assert {{:error, _}, _} = Sim.walk_and_lock(world, id, beside)
    end
  end

  describe "the table of the open cells" do
    test "for each width from 5 to 27, no run stops before the far land, and Best is the table of the config" do
      cfg = Sim.cfg()
      rows = Table.table(cfg, Enum.to_list(5..27), 25)
      best = Keyword.fetch!(cfg, :bridge_best)
      random = Keyword.fetch!(cfg, :bridge_random)

      line = fn name, values ->
        "  #{String.pad_trailing(name, 28)}" <>
          Enum.map_join(values, &String.pad_leading(to_string(&1), 4))
      end

      IO.puts(
        "\n" <>
          Enum.join(
            [
              line.("Width", Enum.map(rows, & &1.width)),
              line.("Best", Enum.map(rows, & &1.best)),
              line.("Random, highest of 25 runs", Enum.map(rows, & &1.high)),
              line.("Random of the config (200)", Enum.map(rows, &random[&1.width]))
            ],
            "\n"
          )
      )

      for row <- rows do
        assert row.stuck == 0, "a run stopped at width #{row.width}"
        assert row.best == best[row.width]
        # No random run is better than Best. The 25 runs are the first 25 of the 200 runs
        # of the config: their highest is not more than the highest of the config.
        assert row.low >= row.best
        assert row.high <= random[row.width]
      end

      # The widths of the plan 0003 table did not change.
      assert Enum.map(rows, & &1.best) |> Enum.take(10) == Enum.take(@best, 10)
    end

    @tag :slow
    @tag timeout: :infinity
    test "200 random runs give the highest Random of the config" do
      cfg = Sim.cfg()
      random = Keyword.fetch!(cfg, :bridge_random)

      for row <- Table.table(cfg, Enum.to_list(5..27), 200) do
        assert row.stuck == 0
        assert row.high == random[row.width]
      end
    end
  end

  describe "the gain of an open cell" do
    test "in the wider phase, the gain is how much the cell makes the highest support of the top row larger" do
      world = world(20)
      grid = world.grid
      rule = world.rule
      start = Sim.open(world)
      :rand.seed(:exsss, 7)

      # A random bridge. At each step of the wider phase, each gain is the increase of the
      # highest support of the top row.
      {_locked, different} =
        Enum.reduce_while(1..200, {%{}, 0}, fn _, {locked, different} ->
          case Support.open_gains(grid, rule, locked, 1, start) do
            [] ->
              {:halt, {locked, different}}

            gains ->
              wider? = locked != %{} and Enum.any?(gains, fn {_cell, gain} -> gain > 0 end)

              different =
                if wider? do
                  top = locked |> Map.keys() |> Enum.map(&Grid.row(grid, &1)) |> Enum.max()
                  before = Support.top_support(grid, Support.calculate(grid, rule, locked), top)

                  for {cell, gain} <- gains do
                    next = Map.put(locked, cell, true)

                    assert gain ==
                             Support.top_support(grid, Support.calculate(grid, rule, next), top) -
                               before

                    assert gain > 0
                  end

                  values = gains |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
                  if length(values) > 1, do: different + 1, else: different
                else
                  different
                end

              {cell, _gain} = Enum.random(gains)
              {:cont, {Map.put(locked, cell, true), different}}
          end
        end)

      # Some steps have cells with a larger gain and cells with a smaller gain: the page
      # shows the first bright and the others weak.
      assert different > 0
    end

    test "in the forward phase, each open cell has the gain 0" do
      world = world(12)
      col = world.piles[1].col
      locked = %{Sim.river_cell(world, 1, col) => true}
      gains = Support.open_gains(world.grid, world.rule, locked, 1, Sim.open(world))
      assert gains != [] and Enum.all?(gains, fn {_cell, gain} -> gain == 0 end)
    end
  end
end
