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
    test "the support rule holds in all the structures of a small river" do
      assert check!("Bridge").distinct_states > 100
    end

    test "the rule holds on a river with a different width in its columns, with lines of 4 bodies" do
      assert check!("BridgeWide").distinct_states > 500
    end

    test "the open cells: one bridge, forward first, and no bridge stops before the far bank" do
      assert check!("BridgeOpen").distinct_states > 20

      # The checks are real: a bridge of this river does not have 3 bodies.
      assert {:error, violation, _stats} =
               Checker.check(spec("BridgeOpen"),
                 invariant_exprs: ["Complete(bodies) => Cardinality(bodies) = 3"]
               )

      assert violation.kind == :invariant
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
    test "all the states of a small world with one player and two spare bodies" do
      assert check!("Colony").distinct_states > 200
    end
  end

  describe "the numbers of the game config" do
    # The contract with the grid, river `k` and the support rule of a real world, in
    # temporary files.
    defp plan_machine(world, dir, k, lines) do
      name = "ColonyPlan#{k}"
      {module, config} = Contract.plan_files(world, name, k, lines)
      File.write!(Path.join(dir, "#{name}.tla"), module)
      File.write!(Path.join(dir, "#{name}.cfg"), config)

      {:ok, machine} =
        Machine.load(Path.join(dir, "#{name}.tla"), paths: [Path.dirname(Contract.spec_path())])

      # The contract permits each number of workers at the start. The test uses the largest.
      {:ok, states} = Machine.init_states(machine)
      state = Enum.max_by(states, &Machine.to_map(machine, &1)["spare"])
      {machine, state}
    end

    # One step of the contract. At a crossing the contract permits each cell of the near
    # bank for the nest: the next state is the state with the nest of the real world.
    defp step!(machine, state, action, args, nest) do
      assert {:ok, nexts} = Machine.step(machine, state, action, args)
      assert nexts != [], "the contract does not permit #{action}(#{inspect(args)})"

      case nexts do
        [{next, nil}] ->
          next

        many ->
          {next, nil} =
            Enum.find(many, fn {next, _} -> Machine.to_map(machine, next)["nest"] == nest end)

          next
      end
    end

    defp bodies(machine, state) do
      Accord.Spec.Value.from_tla(Machine.to_map(machine, state)["bodies"])
    end

    @tag :tmp_dir
    test "the contract and the server have the same open cells on river 1", %{tmp_dir: dir} do
      {world, id} = World.join(World.new(Sim.cfg(seed: 3, spare: 30)), "Tester")
      {machine, state} = plan_machine(world, dir, 1, "")

      # The player takes the highest open cell each time. The contract permits each lock.
      {world, state} =
        Enum.reduce_while(1..20, {world, state}, fn _, {world, state} ->
          if world.stage > 1 do
            {:halt, {world, state}}
          else
            cell = world.open |> Map.keys() |> Enum.max()
            # A cell that is not open is not a step of the contract.
            closed =
              Enum.find(Colony.Grid.neighbors(world.grid, cell), fn other ->
                Colony.Grid.kind(world.grid, other) == :gap and not World.open?(world, other) and
                  not is_map_key(world.locked, other)
              end)

            if closed do
              refute match?(
                       {:ok, [{_, nil}]},
                       Machine.step(machine, state, "HelperLocked", [closed])
                     )
            end

            world = Sim.lock!(world, id, cell)
            {:cont, {world, step!(machine, state, "HelperLocked", [cell], world.nest)}}
          end
        end)

      assert bodies(machine, state) == MapSet.new(World.bridge(world, 1))
      assert MapSet.size(bodies(machine, state)) in 5..7
    end

    @tag :tmp_dir
    test "4 helpers on the grid of the game obey the contract of a bridge", %{tmp_dir: dir} do
      world = World.new(Sim.cfg(helpers: 4, spare: 30, seed: 2, helper_lock_seconds: 4))
      first = plan_machine(world, dir, 1, "INVARIANT AllSupported\n")

      # The helpers build the bridges of river 1 and of river 2. Each lock must be a step
      # of the contract of its river, and the bodies of the world must be the bodies of
      # the contract.
      {world, _machines, count} =
        Enum.reduce_while(1..6000, {world, %{1 => first}, 0}, fn _, {world, machines, count} ->
          {world, events} = World.tick(world)

          {machines, count} =
            Enum.reduce(Enum.reverse(events.locks), {machines, count}, fn {cell, body, _id},
                                                                          {machines, count} ->
              assert body.helper
              k = Colony.Grid.river(world.grid, cell)

              {machine, state} =
                machines[k] || plan_machine(world, dir, k, "INVARIANT AllSupported\n")

              next = step!(machine, state, "HelperLocked", [cell], world.nest)
              assert Machine.check_invariants(machine, next) == :ok
              {Map.put(machines, k, {machine, next}), count + 1}
            end)

          for {_cell, _body, _id} <- Enum.take(events.locks, 1),
              {k, {machine, state}} <- machines do
            assert bodies(machine, state) == MapSet.new(World.bridge(world, k))
          end

          if world.stage >= 3,
            do: {:halt, {world, machines, count}},
            else: {:cont, {world, machines, count}}
        end)

      IO.puts(
        "\n  4 helpers, grid of the game: #{count} locks are steps of the contract, " <>
          "#{world.stage - 1} crossings"
      )

      assert world.stage == 3
      assert count >= 15
    end
  end
end
