defmodule Colony.ContractPlanTest do
  @moduledoc """
  The contract of a bridge with the numbers of the plan, on a river of 9 rows.

  This check is the longest check of the contracts. It is in a module of its own: it runs
  at the same time as the other tests.
  """

  use ExUnit.Case, async: true

  alias Accord.TLA.Checker

  @moduletag timeout: :infinity

  test "a river of 9 rows needs 10 bodies, and no bridge stops before the far bank" do
    path = Path.expand("specs/BridgeNineRows.tla")
    {time, result} = :timer.tc(fn -> Checker.check(path, workers: :auto) end)
    assert {:ok, stats} = result

    IO.puts(
      "\n  BridgeNineRows: #{stats.distinct_states} states, depth #{stats.depth}, " <>
        "#{Float.round(time / 1_000_000, 1)} s"
    )

    assert stats.distinct_states > 500
  end
end
