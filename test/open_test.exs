defmodule Colony.OpenTest do
  @moduledoc "The open cells: a lock is possible only where it helps. Plan 0003, section 4.5."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, Support, World}

  @moduletag timeout: 300_000

  # The table of the plan. A width of 15 rows is not in the plan: no river has it.
  @widths [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18]
  @best [5, 6, 7, 8, 10, 13, 16, 19, 22, 25, 31, 36, 41]
  @plan_random [5, 6, 7, 8, 10, 14, 18, 22, 27, 30, 42, 47, 51]

  defp world(rows, changes \\ []),
    do: World.new(Sim.straight(rows, Keyword.merge([workers: 60], changes)))

  # The cells that are open after the locks into `cells`, in this order.
  defp open_after(world, cells) do
    locked = Map.new(cells, &{&1, true})
    start = Enum.sort(world.open)
    Enum.sort(Support.open(world.grid, world.rule, locked, 1, start))
  end

  describe "the rule" do
    test "with no body, the first row is open, 6 columns or less from the column of the pile" do
      world = world(6)
      col = world.piles[1].col

      assert Enum.sort(world.open) ==
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
        case Support.open(grid, rule, locked, 1, Enum.sort(world.open)) do
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
      assert MapSet.size(world.open) == 0
      assert length(World.bridge(world, 1)) == 5

      # A cell beside the bridge has support, but it is not open.
      [body | _] = World.bridge(world, 1)
      [beside | _] = Enum.reject(Grid.beside(world.grid, body), &is_map_key(world.locked, &1))
      assert Support.can_lock?(world.grid, world.rule, world.locked, beside)
      assert {{:error, _}, _} = Sim.walk_and_lock(world, id, beside)
    end
  end

  describe "the table of the plan" do
    # Builds a bridge on a river with one width. `pick` takes one of the open cells.
    defp build(world, pick) do
      grid = world.grid
      rule = world.rule
      start = Enum.sort(world.open)

      locked =
        Enum.reduce_while(1..400, %{}, fn _, locked ->
          case Support.open(grid, rule, locked, 1, start) do
            [] -> {:halt, locked}
            open -> {:cont, Map.put(locked, pick.(locked, Enum.sort(open)), true)}
          end
        end)

      # No run stops before the far land.
      assert Enum.any?(Map.keys(locked), &Grid.touches_land?(grid, &1, 1))
      map_size(locked)
    end

    # "Best" takes the open cell with the largest gain: the cell that gives the highest
    # support of the top row.
    defp best(world) do
      grid = world.grid

      build(world, fn locked, open ->
        Enum.max_by(open, fn cell ->
          next = Map.put(locked, cell, true)
          top = next |> Map.keys() |> Enum.map(&Grid.row(grid, &1)) |> Enum.max()
          Support.top_support(grid, Support.calculate(grid, world.rule, next), top)
        end)
      end)
    end

    # "Random" takes a random open cell: a player who taps each time the button is bright.
    defp random(world, seed) do
      :rand.seed(:exsss, seed)
      build(world, fn _locked, open -> Enum.random(open) end)
    end

    test "the number of bodies for each width of a river" do
      rows =
        @widths
        |> Task.async_stream(
          fn width ->
            world = world(width)
            runs = for seed <- 1..25, do: random(world, seed)
            {width, best(world), Enum.min(runs), Enum.max(runs)}
          end,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, row} -> row end)

      line = fn name, values ->
        "  #{String.pad_trailing(name, 28)}" <>
          Enum.map_join(values, &String.pad_leading(to_string(&1), 4))
      end

      IO.puts(
        "\n" <>
          Enum.join(
            [
              line.("Width", @widths),
              line.("Best", Enum.map(rows, &elem(&1, 1))),
              line.("Random, lowest of 25 runs", Enum.map(rows, &elem(&1, 2))),
              line.("Random, highest of 25 runs", Enum.map(rows, &elem(&1, 3))),
              line.("Random of the plan", @plan_random)
            ],
            "\n"
          )
      )

      # "Best" is the row of the plan.
      assert Enum.map(rows, &elem(&1, 1)) == @best

      # No random run is better than "Best". The highest random run changes with the
      # random numbers: it is near the row of the plan, not the same.
      for {{_width, best, low, high}, plan} <- Enum.zip(rows, @plan_random) do
        assert low >= best
        assert high <= plan * 1.25
      end
    end
  end
end
