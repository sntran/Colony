defmodule Colony.ProtocolTest do
  @moduledoc "A client that reads the binary messages has the same state as the world."

  use ExUnit.Case, async: true

  alias Colony.{Mirror, Protocol, Sim, World}

  defp same!(world, mirror) do
    assert mirror.tick == world.tick

    workers =
      Map.new(world.workers, fn {id, w} ->
        carry =
          case w.carry do
            nil -> nil
            :egg -> :egg
            _ -> :food
          end

        {id, %{cell: w.cell, carry: carry, kind: w.kind}}
      end)

    assert mirror.workers == workers
    assert mirror.scent == world.scent
    assert mirror.structure == world.supports
    assert mirror.open == world.open
    assert mirror.nest == world.nest
    assert mirror.old_nests == world.old_nests

    assert mirror.food == %{
             nest: world.food_nest,
             stage: world.stage,
             complete: world.complete != nil
           }

    assert mirror.piles ==
             Map.new(world.piles, fn {id, pile} ->
               {id,
                %{
                  cell: pile.cell,
                  units: pile.units,
                  size: pile.size,
                  least: pile.least,
                  far: pile.crossed == nil
                }}
             end)

    for {cell, body} <- world.locked do
      assert %{name: name, time: time, kind: kind, n: n, owner: owner} = mirror.locks[cell]
      assert name == body.name
      assert n == body.n
      assert owner == (body.owner || 0)
      assert time == body.time
      assert kind == if(body.helper, do: 2, else: 1)
    end

    assert Enum.sort(Map.keys(mirror.players)) == Enum.sort(Map.keys(world.players))

    for {id, player} <- world.players do
      assert mirror.names[id] == {player.name, player.helper != nil}
      assert mirror.players[id].carry == (player.carry != nil)
      assert_in_delta mirror.players[id].x, player.x, 0.002
      assert_in_delta mirror.players[id].z, player.z, 0.002
    end
  end

  test "the snapshot has the rivers and the numbers of the support rule" do
    world = World.new(Sim.cfg(spare: 30))
    mirror = Mirror.new(world.grid, Protocol.snapshot(world, 0xFFFF))

    assert mirror.rivers ==
             for(
               river <- Tuple.to_list(world.grid.rivers),
               do: %{start: river.start, widths: Tuple.to_list(river.widths)}
             )

    assert length(mirror.rivers) == 4
    assert mirror.rule == %{bank: 96, costs: [12, 6, 4, 3]}
    assert mirror.you == 0xFFFF
    assert mirror.open == world.open
    assert map_size(mirror.open) == 13
    assert mirror.nest == world.nest
  end

  test "a position of the full world keeps its value" do
    world = World.new(Sim.cfg())
    {x, z} = Colony.Grid.center(world.grid, world.grid.count - 1)
    assert {:ok, x2, z2, _heading} = Protocol.decode_move(Protocol.encode_move(x, z, 0.0))
    assert_in_delta x, x2, 0.002
    assert_in_delta z, z2, 0.002
  end

  test "a client that joins late and reads each tick stays the same as the world" do
    cfg = Sim.cfg(spare: 30, helpers: 4, helper_lock_seconds: 6)
    {world, id} = World.join(World.new(Keyword.merge(cfg, helpers: 0)), "Chi")
    world = Sim.run(world, 35)

    # A lock of a player between two ticks: the snapshot has it, and the next tick has it also.
    world = Sim.lock!(world, id, Sim.river_cell(world, 1, world.piles[1].col))
    world = World.set_helpers(world, 4)
    mirror = Mirror.new(world.grid, Protocol.snapshot(world, id))
    assert mirror.you == id
    assert mirror.names[id] == {"Chi", false}

    {world, mirror} =
      Enum.reduce(1..2500, {world, mirror}, fn n, {world, mirror} ->
        # The helpers go away and come back. The player carries food.
        world =
          case n do
            900 -> World.set_helpers(world, 1)
            1200 -> World.set_helpers(world, 4)
            1000 -> World.put_player(world, id, %{world.players[id] | carry: %{pile: 1, units: 10}})
            1500 -> World.rename(world, id, "Chi Two")
            _ -> world
          end

        {world, events} = World.tick(world)
        mirror = Mirror.apply_tick(mirror, Protocol.tick(world, events))
        same!(world, mirror)
        {world, mirror}
      end)

    # The test had crossings, piles, new workers and bodies of workers that the helpers took.
    assert world.food_nest > 0
    assert world.stage >= 3
    assert map_size(world.piles) >= 3
    assert world.next_worker > 30 or world.free_ids != []
    assert mirror.players[id]
    assert world.old_nests != []
  end

  test "a record is a map that JSON can have" do
    world = World.new(Sim.cfg(spare: 30, carriers: 12, helpers: 4))
    {world, _} = Sim.run_until(world, 1200, &(&1.records != []))
    [record] = world.records
    json = record |> Protocol.record() |> JSON.encode!() |> JSON.decode!()

    assert %{
             "id" => 1,
             "size" => 143,
             "names" => [
               %{"name" => "Helper " <> _, "helper" => true, "bodies" => _, "food" => 0} | _
             ]
           } = json

    assert is_integer(json["seconds"]) and is_integer(json["rows"]) and is_integer(json["left"])
  end

  test "a move from a client keeps its values" do
    binary = Protocol.encode_move(30.25, 5.196, :math.pi() / 2)
    assert byte_size(binary) == 7
    assert {:ok, x, z, heading} = Protocol.decode_move(binary)
    assert_in_delta x, 30.25, 0.002
    assert_in_delta z, 5.196, 0.002
    assert_in_delta heading, :math.pi() / 2, 0.02
    assert Protocol.decode_move(<<1, 2, 3>>) == :error
  end

  test "a tick of 1,000 workers and 8 helpers is small" do
    world = World.new(Sim.cfg(spare: 1000, spare_max: 1000, helpers: 8))

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
