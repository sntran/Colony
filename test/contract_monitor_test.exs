defmodule Colony.ContractMonitorTest do
  @moduledoc """
  The real world, with the TLA+ contract `specs/Colony.tla` as a monitor.

  A test player sends many random messages through `Accord.Spec.Monitor`. The monitor
  follows each message and each event of the world as a step of the contract. A message
  or an event that the contract does not permit is a violation.
  """

  use ExUnit.Case, async: false

  alias Accord.Spec.Monitor
  alias Accord.Test.ViolationCollector
  alias Colony.{Contract, World}

  @moduletag :capture_log
  @players [:p1, :p2]

  defp start(changes) do
    changes = Keyword.merge([helpers: 1, helper_lock_seconds: 20], changes)
    game = Contract.game_config("specs/ColonyPlay.cfg", changes)
    {:ok, server} = Contract.Server.start_link(game)
    ViolationCollector.init()

    {:ok, monitor} =
      Monitor.start_link(Contract,
        upstream: server,
        violation_policy: {ViolationCollector, :handle}
      )

    :ok = Contract.Server.attach(server, monitor)
    world = Contract.Server.world(server)
    %{server: server, monitor: monitor, cells: 0..(world.grid.count - 1)}
  end

  # Sends one message. Then the monitor compares the world with the contract: the locked
  # bodies, the number of spare bodies and the body of each player must be the same.
  defp send!(%{monitor: monitor}, message) do
    reply = Monitor.call(monitor, message, 30_000)
    Monitor.call(monitor, :look, 30_000)
    Monitor.call(monitor, :spare, 30_000)
    for name <- @players, do: Monitor.call(monitor, {:where, name}, 30_000)

    case ViolationCollector.drain() do
      [] ->
        reply

      [violation | _] ->
        flunk("""
        The world does not obey the contract.
          message: #{inspect(message)}, reply: #{inspect(reply)}
          blame:   #{inspect(violation.blame)} (#{inspect(violation.kind)})
          at:      #{inspect(violation.message)} -> #{inspect(violation.reply)}
          reason:  #{violation.context.reason}
          expected reply: #{inspect(violation.expected)}
          states of the contract: #{inspect(violation.context.states)}
        """)
    end
  end

  # Most of the messages are messages that can do something: a move to a cell that
  # touches the cell of the body, a step to the open cells, or a lock into a river cell
  # that touches the body. The other messages are fully random: the world must refuse
  # most of them, as the contract says.
  defp random_message(%{server: server, cells: cells}) do
    world = Contract.Server.world(server)
    grid = world.grid
    ids = Contract.Server.ids(server)
    name = Enum.random(@players)
    body = ids[name] && world.players[ids[name]]
    near = if body, do: Colony.Grid.neighbors(grid, body.cell), else: Enum.to_list(cells)
    gap = Enum.filter(near, &(Colony.Grid.kind(grid, &1) == :gap))
    open = Enum.filter(near, &World.open?(world, &1))

    # The first cell of the way to a cell that touches an open cell.
    step =
      if body do
        Map.keys(world.open)
        |> Enum.flat_map(&Colony.Grid.neighbors(grid, &1))
        |> Enum.filter(&World.walkable?(world, &1))
        |> Enum.map(&Colony.Sim.path(world, body.cell, &1))
        |> Enum.reject(&(&1 in [nil, []]))
        |> Enum.min_by(&length/1, fn -> nil end)
      end

    case :rand.uniform(100) do
      n when n <= 20 and step != nil -> {:move, name, hd(step)}
      n when n <= 34 -> {:move, name, Enum.random(near)}
      n when n <= 42 -> {:move, name, Enum.random(cells)}
      n when n <= 54 and open != [] -> {:lock, name, Enum.random(open)}
      n when n <= 62 and gap != [] -> {:lock, name, Enum.random(gap)}
      n when n <= 70 -> {:lock, name, Enum.random(cells)}
      n when n <= 84 and body == nil -> {:join, name}
      n when n <= 86 and body != nil -> {:leave, name}
      n when n <= 96 -> {:tick, Enum.random(1..12)}
      _ -> {:tick, 40}
    end
  end

  test "a correct run has no violation" do
    context = start(helpers: 0, spare: 1)
    assert send!(context, {:join, :p1}) == :ok
    # The nest is the cell 2. The cells 6 to 11 are the first row of the river.
    assert send!(context, {:move, :p1, 3}) == :ok
    assert send!(context, {:move, :p1, 8}) == :no
    # A cell that is not open: the second row of the river.
    assert send!(context, {:lock, :p1, 14}) == {:error, -1}
    # The lock uses the one spare body of the colony.
    assert {:ok, at} = send!(context, {:lock, :p1, 8})
    assert send!(context, {:where, :p1}) == {:alive, at}
    assert send!(context, :spare) == 0

    # With no spare body, a lock is not possible.
    assert send!(context, {:tick, 12}) == :ok
    world = Contract.Server.world(context.server)
    id = Contract.Server.ids(context.server)[:p1]

    for cell <- Colony.Sim.path(world, world.players[id].cell, 3) do
      assert send!(context, {:move, :p1, cell}) == :ok
    end

    assert send!(context, {:lock, :p1, 9}) == {:error, -1}

    # The nest makes a worker each 10 seconds. Then the lock is possible.
    assert send!(context, {:tick, 100}) == :ok
    assert send!(context, :spare) == 1
    assert {:ok, _at} = send!(context, {:lock, :p1, 9})

    [state] = Monitor.states(context.monitor)
    assert state["bodies"] == MapSet.new([8, 9])
    assert state["life"] == %{"p1" => "alive", "p2" => "out"}
    assert state["spare"] == 0
    assert Contract.Server.events(context.server)[:worker_made] == 1
  end

  test "after a lock, the player has the body of a worker and cannot lock for a moment" do
    context = start(helpers: 0, spare: 5)
    assert send!(context, {:join, :p1}) == :ok
    assert send!(context, {:move, :p1, 3}) == :ok
    assert {:ok, cell} = send!(context, {:lock, :p1, 8})
    assert cell >= 0

    assert [%{"rest" => %{"p1" => true}, "spare" => 4}] = Monitor.states(context.monitor)
    assert send!(context, {:tick, 10}) == :ok
    assert [%{"rest" => %{"p1" => false}}] = Monitor.states(context.monitor)
    assert Contract.Server.events(context.server)[:rested] == 1
  end

  test "the monitor sees a world that does not obey the contract" do
    # A world with a wrong support rule: its bank support is 3, and the contract says 2.
    # It has no helper, thus the lock of the player is the first step that is wrong.
    context = start(bank_support: 3, helpers: 0, spare: 3)
    assert Monitor.call(context.monitor, {:join, :p1}) == :ok
    assert Monitor.call(context.monitor, {:move, :p1, 3}) == :ok
    assert {:ok, _at} = Monitor.call(context.monitor, {:lock, :p1, 8})
    Monitor.call(context.monitor, {:tick, 30})
    world = Contract.Server.world(context.server)

    for cell <- Colony.Sim.path(world, world.players[1].cell, 8) do
      assert Monitor.call(context.monitor, {:move, :p1, cell}) == :ok
    end

    assert ViolationCollector.drain() == []

    # With bank support 2, a second body in a row of its own has no support: the cell
    # is not open. The contract says "error". This world says "ok".
    assert {:accord_violation, violation} = Monitor.call(context.monitor, {:lock, :p1, 14})
    assert {:ok, _at} = violation.reply
    assert violation.blame == :server
    assert violation.kind == :invalid_reply
    assert violation.expected == [["error", -1]]
  end

  for seed <- 1..4 do
    test "random messages of two players obey the contract, seed #{seed}" do
      :rand.seed(:exsss, unquote(seed))
      context = start(seed: unquote(seed))

      # The contract has one river: the test stops at the crossing.
      replies =
        Enum.reduce_while(1..220, %{}, fn _, replies ->
          message = random_message(context)
          reply = send!(context, message)
          reply = if is_tuple(reply), do: elem(reply, 0), else: reply
          replies = Map.update(replies, {elem(message, 0), reply}, 1, &(&1 + 1))
          crossed? = Contract.Server.world(context.server).stage > 1
          if crossed?, do: {:halt, replies}, else: {:cont, replies}
        end)

      # The run used the contract: moves and locks that the world accepted and refused,
      # a helper that locked, bodies that the players took, and new workers of the nest.
      events = Contract.Server.events(context.server)

      for key <- [move: :ok, move: :no, lock: :ok, lock: :error] do
        assert Map.get(replies, key, 0) > 0, "no #{inspect(key)} in #{inspect(replies)}"
      end

      for key <- [:helper_locked, :rested, :worker_made] do
        assert Map.get(events, key, 0) > 0, "no #{key} in #{inspect(events)}"
      end

      if unquote(seed) == 1 do
        world = Contract.Server.world(context.server)

        IO.puts(
          "\n  monitor, seed 1: #{world.tick} ticks, replies #{inspect(Enum.sort(replies))}, " <>
            "events #{inspect(Enum.sort(events))}, #{map_size(world.locked)} locked bodies"
        )
      end
    end
  end
end
