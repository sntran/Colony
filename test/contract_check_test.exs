defmodule Colony.ContractCheckTest do
  @moduledoc """
  The native TLA+ checker of accord checks the contracts in `specs/`.

  The checks with the tag `:slow` do not run in a usual `mix test`. To run all of them:
  `mix test --include slow`, or `mix colony.contracts`.
  """

  use ExUnit.Case, async: false

  alias Accord.TLA.Checker
  alias Accord.TLA.Checker.Machine
  alias Colony.{Contract, Sim, World}

  @moduletag timeout: :infinity

  defp check!(module, opts \\ []) do
    path = Path.expand("specs/#{module}.tla")
    {time, result} = :timer.tc(fn -> Checker.check(path, [workers: :auto] ++ opts) end)

    case result do
      {:ok, stats} ->
        IO.puts(
          "\n  #{module}: #{stats.distinct_states} states, depth #{stats.depth}, " <>
            "#{Float.round(time / 1_000_000, 1)} s"
        )

        stats

      {:error, violation, _stats} ->
        flunk("The checker found a fault in #{module}: #{inspect(violation, limit: 40)}")
    end
  end

  describe "the contract of a bridge" do
    test "the lock rule, the support rule and the fall hold in all the states of a small gap" do
      stats = check!("Bridge")
      assert stats.distinct_states > 500
    end

    test "a bridge one cell wide stops at 7 rows, with the numbers of the plan" do
      # No state has a body after row 7.
      check!("BridgeOneWide")

      # Some state has a body in row 7: the checker finds it as a state that makes
      # "no body in row 7" false, after 7 locks.
      path = Path.expand("specs/BridgeOneWide.tla")
      assert {:error, violation, _stats} = Checker.check(path, invariant_exprs: ["NeverRowSeven"])
      assert violation.kind == :invariant
      assert length(violation.trace) == 8
    end

    @tag :slow
    test "the contract holds in all the states of a larger gap" do
      check!("BridgeWide")
    end
  end

  describe "the contract between a player and the world" do
    @tag :slow
    test "all the states of a small world with one player" do
      stats = check!("Colony")
      assert stats.distinct_states > 5000
    end
  end

  describe "the numbers of the game config" do
    # A config of the contract with the numbers of config/game.exs, in a temporary file.
    defp plan_machine(dir, lines) do
      game = Sim.cfg()
      path = Path.join(dir, "ColonyPlan.cfg")
      File.write!(path, Contract.config_text(game, []) <> lines)
      {:ok, machine} = Machine.load(Contract.spec_path(), config: path)
      {:ok, [state]} = Machine.init_states(machine)
      {game, machine, state}
    end

    defp step!(machine, state, action, args) do
      assert {:ok, [{next, nil}]} = Machine.step(machine, state, action, args),
             "the contract does not permit #{action}(#{inspect(args)})"

      next
    end

    @tag :tmp_dir
    test "a bridge two cells wide crosses the 12 rows", %{tmp_dir: dir} do
      {game, machine, state} = plan_machine(dir, "INVARIANT NeverAcross\n")
      world = World.new(game)

      # The same 24 locks as the test of the world in test/bridge_test.exs.
      state =
        Enum.reduce(1..12, state, fn row, state ->
          assert Machine.check_invariants(machine, state) == :ok

          state
          |> then(&step!(machine, &1, "WorkerLocked", [Sim.gap_cell(world, row, 30)]))
          |> then(&step!(machine, &1, "WorkerLocked", [Sim.gap_cell(world, row, 31)]))
        end)

      # Now a free body can get to the far bank: "never across" is false.
      assert Machine.check_invariants(machine, state) == {:violated, "NeverAcross"}
    end

    @tag :tmp_dir
    test "a bridge one cell wide stops at 7 rows on the grid of the game", %{tmp_dir: dir} do
      {game, machine, state} = plan_machine(dir, "")
      world = World.new(game)

      state =
        Enum.reduce(1..7, state, fn row, state ->
          step!(machine, state, "WorkerLocked", [Sim.gap_cell(world, row, 30)])
        end)

      # No lock is possible in row 8 from the bodies of the bridge.
      for cell <- Colony.Grid.forward(world.grid, Sim.gap_cell(world, 7, 30)) do
        assert Machine.step(machine, state, "WorkerLocked", [cell]) == {:ok, []}
      end
    end

    @tag :tmp_dir
    test "200 workers on the grid of the game obey the contract of a bridge", %{tmp_dir: dir} do
      {game, machine, state} = plan_machine(dir, "INVARIANT AllSupported\n")
      world = World.new(Keyword.merge(game, workers: 200, let_go_seconds: 5, food_units: 40))

      # The scent of the demo starts, stops and starts again. Thus the workers build a
      # bridge, let go, fall and build again. Each change of the bridge must be a step of
      # the contract, and the bodies of the world must be the bodies of the contract.
      {_world, _state, counts} =
        Enum.reduce(1..1800, {World.set_demo(world, true), state, %{}}, fn tick,
                                                                           {world, state, counts} ->
          world =
            case tick do
              500 -> World.set_demo(world, false)
              1300 -> World.set_demo(world, true)
              _ -> world
            end

          {world, events} = World.tick(world)

          steps =
            if(events.let_go == [], do: [], else: [{"WorkersLetGo", MapSet.new(events.let_go)}]) ++
              for {cell, %{kind: :worker}} <- Enum.reverse(events.locks), do: {"WorkerLocked", cell}

          {state, counts} =
            Enum.reduce(steps, {state, counts}, fn {action, arg}, {state, counts} ->
              value = Accord.Spec.Value.to_tla(arg)
              next = step!(machine, state, action, [value])
              assert Machine.check_invariants(machine, next) == :ok
              {next, Map.update(counts, action, 1, &(&1 + 1))}
            end)

          if steps != [] do
            bodies = Accord.Spec.Value.from_tla(Machine.to_map(machine, state)["workerBodies"])
            assert bodies == MapSet.new(Map.keys(world.locked))
          end

          {world, state, counts}
        end)

      IO.puts("\n  200 workers, grid of the game: steps of the contract #{inspect(counts)}")
      assert counts["WorkerLocked"] >= 19
      assert counts["WorkersLetGo"] >= 1
    end
  end
end
