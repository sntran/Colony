defmodule Colony.ContractCheckTest do
  @moduledoc """
  The native TLA+ checker of accord checks the contracts in `specs/`.

  `mix colony.contracts` runs the same checks.
  """

  use ExUnit.Case, async: false

  alias Accord.TLA.Checker
  alias Accord.TLA.Checker.Machine
  alias Colony.{Contract, Sim, World}

  @moduletag timeout: :infinity

  defp spec(module), do: Path.expand("specs/#{module}.tla")

  defp check!(module) do
    {time, result} = :timer.tc(fn -> Checker.check(spec(module), workers: :auto) end)

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
    test "the lock rule and the support rule hold in all the states of a small river" do
      assert check!("Bridge").distinct_states > 100
    end

    test "the rules hold on a river with a different width in its columns, with lines of 4 bodies" do
      assert check!("BridgeWide").distinct_states > 500
    end

    test "a bridge one body wide stops at 7 rows, with the numbers of the plan" do
      # No state has a body after row 7.
      check!("BridgeOneWide")

      # Some state has a body in row 7: the checker finds it as a state that makes
      # "no body in row 7" false, after 7 locks.
      assert {:error, violation, _stats} =
               Checker.check(spec("BridgeOneWide"), invariant_exprs: ["NeverRowSeven"])

      assert violation.kind == :invariant
      assert length(violation.trace) == 8
    end

    test "a bridge two bodies wide stops at 15 rows, and three bodies wide at 23" do
      check!("BridgeTwoWide")
      check!("BridgeThreeWide")

      # The checks are real: a different row number is false.
      for {module, wrong} <- [{"BridgeTwoWide", 14}, {"BridgeTwoWide", 16}, {"BridgeThreeWide", 22}] do
        assert {:error, _violation, _stats} =
                 Checker.check(spec(module), invariant_exprs: ["FullStopsAt(#{wrong})"])
      end
    end
  end

  describe "the contract between a player and the world" do
    test "all the states of a small world with one player" do
      assert check!("Colony").distinct_states > 400
    end
  end

  describe "the numbers of the game config" do
    # The contract with the grid, the river and the support rule of a real world, in
    # temporary files.
    defp plan_machine(world, dir, lines) do
      {module, config} = Contract.plan_files(world, "ColonyPlan", lines)
      File.write!(Path.join(dir, "ColonyPlan.tla"), module)
      File.write!(Path.join(dir, "ColonyPlan.cfg"), config)

      {:ok, machine} =
        Machine.load(Path.join(dir, "ColonyPlan.tla"), paths: [Path.dirname(Contract.spec_path())])

      {:ok, [state]} = Machine.init_states(machine)
      {machine, state}
    end

    defp step!(machine, state, action, args) do
      assert {:ok, [{next, nil}]} = Machine.step(machine, state, action, args),
             "the contract does not permit #{action}(#{inspect(args)})"

      next
    end

    @tag :tmp_dir
    test "the contract and the server have the same river and the same rule", %{tmp_dir: dir} do
      world = World.new(Sim.cfg(seed: 3))
      {machine, state} = plan_machine(world, dir, "")
      col = world.pile.col

      # A bridge one body wide in the column of the pile.
      state =
        Enum.reduce(1..world.pile.width, state, fn row, state ->
          cell = Sim.river_cell(world, row, col)
          assert World.can_lock?(world, cell) or row > 1
          step!(machine, state, "HelperLocked", [cell])
        end)

      bodies = Accord.Spec.Value.from_tla(Machine.to_map(machine, state)["bodies"])
      assert MapSet.size(bodies) == world.pile.width
    end

    @tag :tmp_dir
    test "4 helpers on the grid of the game obey the contract of a bridge", %{tmp_dir: dir} do
      world = World.new(Sim.cfg(helpers: 4, workers: 30, seed: 2, pile_units: 60))
      {machine, state} = plan_machine(world, dir, "INVARIANT AllSupported\n")

      # The helpers build bridges to 3 piles. Each lock must be a step of the contract,
      # and the bodies of the world must be the bodies of the contract.
      {world, _state, count} =
        Enum.reduce_while(1..6000, {world, state, 0}, fn _, {world, state, count} ->
          {world, events} = World.tick(world)

          {state, count} =
            Enum.reduce(Enum.reverse(events.locks), {state, count}, fn {cell, body, _id},
                                                                       {state, count} ->
              assert body.helper
              next = step!(machine, state, "HelperLocked", [cell])
              assert Machine.check_invariants(machine, next) == :ok
              {next, count + 1}
            end)

          if events.locks != [] do
            bodies = Accord.Spec.Value.from_tla(Machine.to_map(machine, state)["bodies"])
            assert bodies == MapSet.new(Map.keys(world.locked))
          end

          if world.pile.id >= 3 and Sim.way_to_pile?(world) and count >= 30,
            do: {:halt, {world, state, count}},
            else: {:cont, {world, state, count}}
        end)

      IO.puts(
        "\n  4 helpers, grid of the game: #{count} locks are steps of the contract, pile #{world.pile.id}"
      )

      assert count >= 30
    end
  end
end
