defmodule Colony.ProtocolTest do
  @moduledoc "A client that reads the binary messages has the same state as the world."

  use ExUnit.Case, async: true

  alias Colony.{Mirror, Protocol, Sim, World}

  defp same!(world, mirror) do
    assert mirror.tick == world.tick

    workers =
      Map.new(world.workers, fn {id, w} -> {id, {w.cell, if(w.carry, do: 1, else: 0)}} end)

    assert mirror.workers == workers
    assert mirror.scent == world.scent
    assert mirror.structure == world.supports

    assert mirror.food == %{
             id: world.pile.id,
             cell: world.pile.cell,
             units: world.pile.units,
             nest: world.food_nest
           }

    for {cell, body} <- world.locked do
      assert %{name: name, time: time, kind: kind} = mirror.locks[cell]
      assert name == body.name
      assert time == body.time
      assert kind == if(body.helper, do: 2, else: 1)
    end

    alive = for {id, %{state: :alive}} <- world.players, do: id
    assert Enum.sort(Map.keys(mirror.players)) == Enum.sort(alive)

    for {id, player} <- world.players do
      assert mirror.names[id] == {player.name, player.helper != nil}
    end
  end

  test "the snapshot has the river and the numbers of the support rule" do
    world = World.new(Sim.cfg(workers: 30))
    mirror = Mirror.new(world.grid, Protocol.snapshot(world, 0xFFFF))
    assert mirror.river == Tuple.to_list(world.grid.river)
    assert mirror.rule == %{bank: 96, costs: [12, 6, 4, 3]}
    assert mirror.you == 0xFFFF
  end

  test "a client that joins late and reads each tick stays the same as the world" do
    cfg = Sim.cfg(workers: 30, helpers: 4, pile_units: 40)
    {world, id} = World.join(World.new(cfg), "Chi")
    world = Sim.run(world, 35)

    # A lock of a player between two ticks: the snapshot has it, and the next tick has it also.
    world = Sim.lock!(world, id, Sim.river_cell(world, 1, 20))
    mirror = Mirror.new(world.grid, Protocol.snapshot(world, id))
    assert mirror.you == id
    assert mirror.names[id] == {"Chi", false}

    {world, mirror} =
      Enum.reduce(1..2500, {world, mirror}, fn n, {world, mirror} ->
        # The helpers go away and come back.
        world =
          case n do
            900 -> World.set_helpers(world, 1)
            1200 -> World.set_helpers(world, 4)
            _ -> world
          end

        {world, events} = World.tick(world)
        mirror = Mirror.apply_tick(mirror, Protocol.tick(world, events))
        same!(world, mirror)
        {world, mirror}
      end)

    # The test had piles, new workers and bodies of workers that the helpers took.
    assert world.food_nest > 0
    assert world.pile.id >= 2
    assert world.next_worker > 30 or world.free_ids != []
    assert mirror.players[id]
  end

  test "a record is a map that JSON can have" do
    world = World.new(Sim.cfg(workers: 30, helpers: 4))
    {world, _} = Sim.run_until(world, 1200, &(&1.records != []))
    [record] = world.records
    json = record |> Protocol.record() |> JSON.encode!() |> JSON.decode!()

    assert %{
             "id" => 1,
             "names" => [%{"name" => "Helper " <> _, "helper" => true, "bodies" => _} | _]
           } = json

    assert is_integer(json["seconds"]) and is_integer(json["rows"]) and is_integer(json["food"])
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

  test "a tick of 1,000 workers and 8 helpers is small" do
    world = World.new(Sim.cfg(workers: 1000, workers_max: 1000, helpers: 8))

    {_world, bytes} =
      Enum.reduce(1..600, {world, 0}, fn _, {world, bytes} ->
        {world, events} = World.tick(world)
        {world, bytes + byte_size(Protocol.tick(world, events))}
      end)

    per_second = bytes / 60

    IO.puts(
      "\n  1,000 workers and 8 helpers: #{round(per_second)} bytes each second in the tick messages"
    )

    assert per_second < 30_000
  end
end
