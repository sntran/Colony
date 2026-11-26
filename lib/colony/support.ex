defmodule Colony.Support do
  @moduledoc """
  The support rule.

  A bank cell that touches the river has the bank support. A locked body takes the highest
  support of the cells that it touches, then it subtracts its cost.

  The cost of a body is 1 divided by `n`. `n` is the number of locked bodies in the line of
  bodies with no hole, in the same row, that contains the body. The largest `n` that counts
  is `row_max`. Thus each body beside a body helps.

  All the numbers here are integers. With `row_max` 4, the costs are 1, 1/2, 1/3 and 1/4.
  Each one is a whole number of twelfths: 12, 6, 4 and 3. The bank support 8 is 96.

  The functions take the set of locked cells as a map. Only the keys are used.
  """

  alias Colony.Grid

  @doc "Reads the numbers of the rule from the game config and makes them integers."
  def rule(cfg) do
    row_max = Keyword.fetch!(cfg, :row_max)
    scale = Enum.reduce(1..row_max, 1, fn n, acc -> div(acc * n, Integer.gcd(acc, n)) end)
    bank = Keyword.fetch!(cfg, :bank_support) * scale
    true = bank == trunc(bank)

    %{
      scale: scale,
      bank: trunc(bank),
      row_max: row_max,
      # costs: the cost of a body in a line of 1, 2, ... bodies.
      costs: List.to_tuple(for n <- 1..row_max, do: div(scale, n))
    }
  end

  @doc "The number of locked bodies in the line of bodies, in the row of the cell, that contains the cell."
  def line(grid, locked, cell) do
    width = grid.width
    row = div(cell, width)
    1 + count(locked, cell, -1, row, width) + count(locked, cell, 1, row, width)
  end

  defp count(locked, cell, step, row, width) do
    next = cell + step

    if next >= 0 and div(next, width) == row and is_map_key(locked, next) do
      1 + count(locked, next, step, row, width)
    else
      0
    end
  end

  @doc "The cost of a body in a cell. The cell is in `locked`, or a body will be there."
  def cost(grid, rule, locked, cell) do
    elem(rule.costs, min(line(grid, locked, cell), rule.row_max) - 1)
  end

  @doc """
  Calculates the support of each locked cell.

  The result is a map from cell to support. A locked cell that no bank can reach is not in
  the result.
  """
  def calculate(grid, rule, locked) do
    costs = Map.new(locked, fn {cell, _} -> {cell, cost(grid, rule, locked, cell)} end)
    spread(grid, rule, costs)
  end

  defp spread(grid, rule, costs) do
    queue =
      for {cell, cost} <- costs, Grid.touches_bank?(grid, cell), reduce: :gb_sets.empty() do
        queue -> :gb_sets.add({-(rule.bank - cost), cell}, queue)
      end

    spread(grid, costs, queue, %{})
  end

  # Takes the cell with the highest support first. Thus the first value of a cell is its
  # highest value.
  defp spread(grid, costs, queue, done) do
    if :gb_sets.is_empty(queue) do
      done
    else
      {{negative, cell}, queue} = :gb_sets.take_smallest(queue)

      if is_map_key(done, cell) do
        spread(grid, costs, queue, done)
      else
        support = -negative
        done = Map.put(done, cell, support)

        queue =
          for next <- Grid.neighbors(grid, cell),
              is_map_key(costs, next),
              not is_map_key(done, next),
              reduce: queue do
            queue -> :gb_sets.add({-(support - Map.fetch!(costs, next)), next}, queue)
          end

        spread(grid, costs, queue, done)
      end
    end
  end

  @doc """
  Removes the locked cells that have support 0 or less, again and again, until all the
  cells that stay have support.

  Returns `{supports, fallen}`. `fallen` is the list of the cells that fall.
  """
  def settle(grid, rule, locked), do: settle(grid, rule, locked, [])

  defp settle(grid, rule, locked, fallen) do
    supports = calculate(grid, rule, locked)

    case for {cell, _} <- locked, Map.get(supports, cell, 0) <= 0, do: cell do
      [] -> {supports, fallen}
      cells -> settle(grid, rule, Map.drop(locked, cells), cells ++ fallen)
    end
  end

  @doc "The locked cells that touch each other, from one locked cell."
  def group(grid, locked, cell), do: group(grid, locked, [cell], MapSet.new([cell]))

  defp group(_grid, _locked, [], seen), do: seen

  defp group(grid, locked, [cell | rest], seen) do
    more =
      for next <- Grid.neighbors(grid, cell),
          is_map_key(locked, next),
          not MapSet.member?(seen, next),
          do: next

    group(grid, locked, more ++ rest, Enum.into(more, seen))
  end

  @doc """
  The supports of a bridge if a body locks into an empty river cell.

  The result is a map from cell to support, for the new cell and for all the locked cells
  that touch it, directly or through other locked cells. A new body changes the cost of
  all the bodies of its line, and each change can go from body to body. Thus this is a
  full calculation for that group of bodies.
  """
  def with_body(grid, rule, locked, cell) do
    locked = Map.put(locked, cell, true)
    cells = group(grid, locked, cell)
    costs = Map.new(cells, fn c -> {c, cost(grid, rule, locked, c)} end)
    spread(grid, rule, costs)
  end

  @doc "The support that a body gets if it locks into an empty river cell, or 0."
  def support_for(grid, rule, locked, cell) do
    grid |> with_body(rule, locked, cell) |> Map.get(cell, 0)
  end

  @doc "True if a body can lock into the cell: the cell is an empty river cell and the support will be more than 0."
  def can_lock?(grid, rule, locked, cell) do
    Grid.kind(grid, cell) == :gap and not is_map_key(locked, cell) and
      has_source?(grid, locked, cell) and support_for(grid, rule, locked, cell) > 0
  end

  # A cell that touches no bank and no body has no support. This is the usual case.
  defp has_source?(grid, locked, cell) do
    Enum.any?(Grid.neighbors(grid, cell), &(Grid.kind(grid, &1) != :gap or is_map_key(locked, &1)))
  end

  @doc """
  The reach of a bridge: how far it can grow, one body wide, in a straight line to the far bank.

  `supports` are the supports of the bodies of the bridge, and `locked` has these bodies.
  Returns `{row, bank?}`: the highest river row that the bridge can get to, and true if
  it can get to the far bank.
  """
  def reach(grid, rule, locked, supports) do
    Enum.reduce(supports, {0, false}, fn {cell, support}, best ->
      max_reach(best, grow(grid, rule, locked, cell, support))
    end)
  end

  defp max_reach({row_a, bank_a} = a, {row_b, bank_b} = b) do
    cond do
      bank_a != bank_b -> if bank_a, do: a, else: b
      row_a >= row_b -> a
      true -> b
    end
  end

  # Goes from a body to the next row, again and again, while a body there has support.
  defp grow(grid, rule, locked, cell, support) do
    row = Grid.river_row(grid, cell)

    case Grid.forward(grid, cell) do
      [next | _] ->
        cond do
          Grid.kind(grid, next) != :gap ->
            {row, true}

          is_map_key(locked, next) ->
            {row, false}

          true ->
            locked = Map.put(locked, next, true)
            after_cost = support - cost(grid, rule, locked, next)
            if after_cost > 0, do: grow(grid, rule, locked, next, after_cost), else: {row, false}
        end

      [] ->
        {row, false}
    end
  end
end
