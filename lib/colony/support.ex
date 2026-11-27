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
  The open cells of river `k`: the cells where a lock is possible and helps.

  `start` has the cells for the first body of the bridge. The rules:

  1. With no body in the river, the cells of `start` are open.
  2. A bridge that touches land `k` is complete. It has no open cell.
  3. Forward first. If a lock is possible in a cell of the row after the top row, and the
     cell touches the bridge, only these cells are open.
  4. If not, a cell that touches the bridge is open if a body there makes the highest
     support of the top row larger.
  """
  def open(grid, rule, locked, k, start) do
    grid |> open_gains(rule, locked, k, start) |> Enum.map(&elem(&1, 0))
  end

  @doc """
  The open cells of river `k` with the gain of each: `[{cell, gain}]`.

  In the "wider" phase, the gain is how much a body in the cell makes the highest support
  of the top row larger, as an integer of the rule. In the other phases the gain is 0: each
  open cell helps the same.
  """
  def open_gains(grid, rule, locked, k, start) do
    bridge = for {cell, _} <- locked, Grid.river(grid, cell) == k, do: cell

    cond do
      bridge == [] ->
        Enum.map(start, &{&1, 0})

      Enum.any?(bridge, &Grid.touches_land?(grid, &1, k)) ->
        []

      true ->
        top = bridge |> Enum.map(&Grid.row(grid, &1)) |> Enum.max()

        ahead =
          for cell <- bridge,
              Grid.row(grid, cell) == top,
              next <- Grid.forward(grid, cell),
              can_lock?(grid, rule, locked, next),
              uniq: true,
              do: {next, 0}

        if ahead == [], do: wider(grid, rule, locked, k, bridge, top), else: ahead
    end
  end

  defp wider(grid, rule, locked, k, bridge, top) do
    now = calculate(grid, rule, Map.take(locked, bridge))
    before = top_support(grid, now, top)

    cells =
      for cell <- bridge,
          next <- Grid.neighbors(grid, cell),
          Grid.river(grid, next) == k,
          not is_map_key(locked, next),
          uniq: true,
          do: next

    for cell <- cells,
        supports = with_body(grid, rule, locked, cell),
        Map.get(supports, cell, 0) > 0,
        gain = top_support(grid, supports, top) - before,
        gain > 0,
        do: {cell, gain}
  end

  @doc "The highest support of the bodies of a row."
  def top_support(grid, supports, row) do
    Enum.reduce(supports, 0, fn {cell, support}, best ->
      if Grid.row(grid, cell) == row, do: max(best, support), else: best
    end)
  end
end
