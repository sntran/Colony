defmodule Colony.ProtocolTest do
  @moduledoc "A client that reads the binary messages has the same state as the world."

  use ExUnit.Case, async: true

  alias Colony.{Mirror, Protocol, Sim, World}

  defp same!(world, mirror) do
    assert mirror.tick == world.tick

    workers = Map.new(world.workers, fn {id, w} -> {id, {w.cell, if(w.carry, do: 1, else: 0)}} end)
    assert mirror.workers == workers

    assert mirror.scent == world.scent
    assert mirror.structure == world.supports
    assert Enum.sort(mirror.frontier) == Enum.sort(world.frontier)
    assert mirror.food == {world.food_pile, world.food_nest}

    for {cell, body} <- world.locked do
      assert %{name: name, time: time} = mirror.locks[cell]
      assert name == body.name
      assert time == body.time
    end

    alive = for {id, %{state: :alive}} <- world.players, do: id
    assert Enum.sort(Map.keys(mirror.players)) == Enum.sort(alive)
  end

  test "a client that joins late and reads each tick stays the same as the world" do
    cfg = Sim.cfg(workers: 200, food_units: 40, food_refill_seconds: 20, let_go_seconds: 5)
    {world, id} = World.join(World.new(cfg), "Chi")
    world = world |> World.set_demo(true) |> Sim.run(35)

    # A lock of a player between two ticks: the snapshot has it, and the next tick has it also.
    world = Sim.lock!(world, id, Sim.gap_cell(world, 1, 20))
    mirror = Mirror.new(world.grid, Protocol.snapshot(world, id))
    assert mirror.you == id
    assert mirror.names[id] == "Chi"

    {world, mirror} =
      Enum.reduce(1..1500, {world, mirror}, fn n, {world, mirror} ->
        # The scent of the demo stops and starts. Thus bodies let go and fall in this test.
        world =
          case n do
            300 -> World.set_demo(world, false)
            900 -> World.set_demo(world, true)
            _ -> world
          end

        {world, events} = World.tick(world)
        mirror = Mirror.apply_tick(mirror, Protocol.tick(world, events))
        same!(world, mirror)
        {world, mirror}
      end)

    assert world.food_nest > 0
    assert mirror.players[id]
  end

  test "a move from a client keeps its values" do
    binary = Protocol.encode_move(30.25, 5.196, :math.pi() / 2, true)
    assert byte_size(binary) == 6
    assert {:ok, x, z, heading, true} = Protocol.decode_move(binary)
    assert_in_delta x, 30.25, 0.001
    assert_in_delta z, 5.196, 0.001
    assert_in_delta heading, :math.pi() / 2, 0.02
    assert Protocol.decode_move(<<1, 2, 3>>) == :error
  end

  test "a tick of 1,000 workers is small" do
    world = World.new(Sim.cfg(workers: 1000)) |> World.set_demo(true)

    {_world, bytes} =
      Enum.reduce(1..600, {world, 0}, fn _, {world, bytes} ->
        {world, events} = World.tick(world)
        {world, bytes + byte_size(Protocol.tick(world, events))}
      end)

    per_second = bytes / 60
    IO.puts("\n  1,000 workers: #{round(per_second)} bytes each second in the tick messages")
    assert per_second < 30_000
  end
end
