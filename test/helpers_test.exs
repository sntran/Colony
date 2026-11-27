defmodule Colony.HelpersTest do
  @moduledoc "The helpers: bodies that the server controls with the rules of a player. Plan 0003, 4.14."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  @moduletag timeout: 300_000

  test "the helpers have the names Helper 1, Helper 2 and so on" do
    world = World.new(Sim.cfg(helpers: 3))
    names = for {_id, player} <- world.players, do: player.name
    assert Enum.sort(names) == ["Helper 1", "Helper 2", "Helper 3"]
    assert Enum.all?(world.players, fn {_id, player} -> player.helper != nil end)

    # The number of helpers can change.
    world = World.set_helpers(world, 1)
    assert [{_id, %{name: "Helper 1"}}] = Map.to_list(world.players)
    assert map_size(World.set_helpers(world, 0).players) == 0
  end

  test "four helpers and no player complete the four crossings" do
    world = World.new(Sim.cfg(helpers: 4, spare: 30, seed: 1))

    {world, times, locks} =
      Enum.reduce_while(1..12_000, {world, [], []}, fn tick, {world, times, locks} ->
        {world, events} = World.tick(world)

        times =
          times ++
            for(%{first: true} = record <- events.records, do: {record.id, tick, record.bodies})

        locks = locks ++ for({_cell, body, _id} <- events.locks, do: {tick, body.name})

        if world.complete,
          do: {:halt, {world, times, locks}},
          else: {:cont, {world, times, locks}}
      end)

    assert world.complete != nil
    assert Enum.map(times, &elem(&1, 0)) == [1, 2, 3, 4]

    IO.puts(
      "\n  4 helpers, the four crossings: " <>
        Enum.map_join(times, ", ", fn {k, tick, bodies} ->
          "river #{k} after #{div(tick, 10)} s with #{bodies} bodies"
        end) <> ". The world is complete after #{div(world.tick, 10)} s."
    )

    # The first bridge is complete in less than 60 seconds of world time.
    [{1, first, _} | _] = times
    assert first < 600

    # All the helpers together lock one time each 4 seconds, and they lock in turn.
    ticks = Enum.map(locks, &elem(&1, 0))
    for [a, b] <- Enum.chunk_every(ticks, 2, 1, :discard), do: assert(b - a >= 40)
    names = locks |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    assert length(names) == 4

    for [a, b] <- locks |> Enum.map(&elem(&1, 1)) |> Enum.chunk_every(2, 1, :discard) do
      assert a != b
    end

    # Each record has helpers only.
    for record <- world.records do
      assert Enum.all?(record.names, &(&1.helper and String.starts_with?(&1.name, "Helper ")))
      assert Enum.sum(Enum.map(record.names, & &1.bodies)) == record.bodies
    end
  end

  test "a helper takes the body of a worker at a lock, as a player does" do
    world = World.new(Sim.cfg(helpers: 1, spare: 5))
    {world, _} = Sim.run_until(world, 600, &(map_size(&1.locked) == 1))
    assert World.spare(world) == 4
    [{_id, helper}] = Map.to_list(world.players)
    assert helper.took != nil
    assert [{_cell, %{name: "Helper 1", helper: true}}] = Map.to_list(world.locked)
  end

  test "a helper obeys the guide: with no spare body, it carries food to the nest" do
    cfg =
      Sim.cfg(
        helpers: 2,
        spare: 7,
        carriers: 0,
        carriers_per_crossing: 0,
        rivers: [{5, 5}, {9, 9}],
        spare_low: 0,
        helper_lock_seconds: 2
      )

    world = World.new(cfg)

    # The helpers make the bridge of river 1. Then the colony has fewer spare bodies than
    # helpers: after a lock, the guide shows the pile first.
    {world, ticks} = Sim.run_until(world, 3000, &(&1.stage == 2))
    assert ticks != nil

    # The guide shows the pile: the helpers carry 10 units each time. The nest makes spare
    # bodies from the food, and the helpers lock again.
    {world, ticks} = Sim.run_until(world, 3000, &(Map.values(&1.helper_food) |> Enum.sum() >= 20))
    assert ticks != nil

    assert Enum.all?(world.helper_food, fn {name, units} ->
             String.starts_with?(name, "Helper ") and units > 0
           end)

    locks = map_size(world.locked)
    {world, ticks} = Sim.run_until(world, 1200, &(map_size(&1.locked) > locks))
    assert ticks != nil
  end

  test "a helper with food goes to the nest and never locks with food" do
    cfg =
      Sim.cfg(
        helpers: 3,
        spare: 8,
        carriers: 0,
        rivers: [{5, 5}, {9, 9}],
        spare_low: 0,
        helper_lock_seconds: 2
      )

    world = World.new(cfg)

    Enum.reduce(1..3000, world, fn _, world ->
      {next, events} = World.tick(world)

      for {_cell, _body, id} <- events.locks do
        # The body that locked carried no food.
        assert world.players[id].carry == nil
      end

      next
    end)
  end

  defp lock_by_guide(world, id, tries) when tries > 0 do
    {:open, cell, stand, _path} = Colony.Guide.target(world, world.players[id])
    world = Sim.walk(world, id, stand)

    case World.lock(world, id, cell) do
      {:ok, world} -> world
      _ -> lock_by_guide(Sim.run(world, 1), id, tries - 1)
    end
  end

  test "helpers build with a player: a bridge has the names of the two" do
    cfg = Sim.cfg(helpers: 3, spare: 30, rivers: [{7, 7}, {9, 9}])
    {world, id} = World.join(World.new(cfg), "Dara")
    # Dara follows the guide to an open cell and locks. A helper can get the cell first:
    # then Dara follows the guide again.
    world = lock_by_guide(world, id, 10)
    {world, ticks} = Sim.run_until(world, 1200, &(&1.records != []))
    assert ticks != nil
    [record] = world.records
    assert Enum.any?(record.names, &(&1.name == "Dara" and not &1.helper and &1.bodies == 1))
    assert Enum.any?(record.names, & &1.helper)
  end
end
