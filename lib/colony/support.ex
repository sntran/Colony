defmodule Colony.Support do
  @moduledoc """
  The support rule.

  A bank cell that touches the gap has the bank support. A locked body takes the highest
  support of the cells that it touches, then it subtracts its cost. The cost is lower when
  a locked body is beside it in the same row.

  The functions here take the set of locked cells as a map. Only the keys are used.
  """

  alias Colony.Grid

  @doc "Reads the three numbers of the rule from the game config."
  def rule(cfg) do
    %{
      bank: Keyword.fetch!(cfg, :bank_support) * 1.0,
      alone: Keyword.fetch!(cfg, :cost_alone) * 1.0,
      beside: Keyword.fetch!(cfg, :cost_beside) * 1.0
    }
  end

  @doc "True if no locked body is beside the cell in the same row."
  def alone?(grid, locked, cell) do
    not Enum.any?(Grid.beside(grid, cell), &is_map_key(locked, &1))
  end

  @doc "The cost of a body in a cell."
  def cost(grid, rule, locked, cell) do
    if alone?(grid, locked, cell), do: rule.alone, else: rule.beside
  end

  @doc """
  Calculates the support of each locked cell.

  The result is a map from cell to support. A locked cell that no bank can reach is not in
  the result.
  """
  def calculate(grid, rule, locked) do
    costs = Map.new(locked, fn {cell, _} -> {cell, cost(grid, rule, locked, cell)} end)

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

    case for {cell, _} <- locked, Map.get(supports, cell, 0.0) <= 0, do: cell do
      [] -> {supports, fallen}
      cells -> settle(grid, rule, Map.drop(locked, cells), cells ++ fallen)
    end
  end

  @doc """
  The support that a body gets if it locks into an empty gap cell.

  `supports` is the result of `calculate/3` for `locked`. The function does not calculate
  all the grid again. A new body can change the cost only of the bodies beside it. The
  bodies beside it touch the new cell. Thus the highest support near the new cell comes
  from the values that are known, with that change of cost.
  """
  def support_for(grid, rule, locked, supports, cell) do
    beside = Enum.filter(Grid.beside(grid, cell), &is_map_key(locked, &1))
    cost = if beside == [], do: rule.alone, else: rule.beside

    values =
      for next <- Grid.neighbors(grid, cell),
          Grid.kind(grid, next) != :gap or is_map_key(supports, next) do
        cond do
          Grid.kind(grid, next) != :gap ->
            rule.bank

          next in beside and alone?(grid, locked, next) ->
            Map.fetch!(supports, next) + rule.alone - rule.beside

          true ->
            Map.fetch!(supports, next)
        end
      end

    case values do
      [] -> nil
      values -> Enum.max(values) - cost
    end
  end

  @doc "True if a body can lock into the cell: the cell is an empty gap cell and the support will be more than 0."
  def can_lock?(grid, rule, locked, supports, cell) do
    Grid.kind(grid, cell) == :gap and not is_map_key(locked, cell) and
      case support_for(grid, rule, locked, supports, cell) do
        nil -> false
        support -> support > 0
      end
  end
end
