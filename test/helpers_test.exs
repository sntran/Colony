defmodule Colony.HelpersTest do
  @moduledoc "Plan 0002, section 4.6: a helper is a body that the server controls with the rules of a player."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  defp helpers(world), do: for({_id, %{helper: %{}} = player} <- world.players, do: player)

  test "the helpers have the names Helper 1, Helper 2 and so on" do
    world = World.new(Sim.cfg(helpers: 3, workers: 30))

    assert world |> helpers() |> Enum.map(& &1.name) |> Enum.sort() == [
             "Helper 1",
             "Helper 2",
             "Helper 3"
           ]

    {_world, events} = World.take_events(world)
    assert Enum.all?(events.names, fn {_id, _name, helper?} -> helper? end)
  end

  test "the demo mode has 4 helpers, and they go away when the demo stops" do
    world = World.new(Sim.cfg(workers: 30))
    assert helpers(world) == []
    world = World.set_demo(world, true)
    assert length(helpers(world)) == 4
    world = Sim.run(world, 300)
    assert map_size(world.locked) > 0
    world = World.set_demo(world, false)
    assert helpers(world) == []
    # The locked bodies of the helpers stay.
    assert map_size(world.locked) > 0
  end

  test "four helpers and no player complete the first bridge in less than 60 seconds" do
    for seed <- 1..5 do
      world = World.new(Sim.cfg(helpers: 4, workers: 30, seed: seed))
      {world, ticks} = Sim.run_until(world, 600, &Sim.way_to_pile?/1)
      assert ticks != nil, "seed #{seed}: no complete bridge in 60 seconds"

      # The bridge grows slowly: a person can see it.
      assert ticks >= 150, "seed #{seed}: the bridge was complete after #{ticks / 10} s"

      # Each locked body is the body of a helper.
      assert Enum.all?(world.locked, fn {_cell, body} -> body.helper end)
      assert world.locked |> Map.values() |> Enum.map(& &1.name) |> Enum.uniq() |> length() >= 3

      # Then food goes across, and the first food makes a record.
      {world, food_ticks} = Sim.run_until(world, 600, &(&1.food_nest > 0))
      assert food_ticks != nil, "seed #{seed}: no food 60 seconds after the bridge"
      assert [%{id: 1, names: names}] = world.records
      assert Enum.all?(names, & &1.helper)

      if seed == 1 do
        IO.puts(
          "\n  4 helpers: first bridge after #{ticks / 10} s with #{map_size(world.locked)} bodies, " <>
            "first food #{food_ticks / 10} s later"
        )
      end
    end
  end

  test "a helper locks one time each 16 seconds at most, and the helpers lock in turn" do
    world = World.new(Sim.cfg(helpers: 4, workers: 30))

    {_world, locks} =
      Enum.reduce(1..600, {world, []}, fn tick, {world, locks} ->
        {world, events} = World.tick(world)
        {world, locks ++ for({_cell, body, _id} <- events.locks, do: {tick, body.name})}
      end)

    assert length(locks) >= 5

    # The same helper: 16 seconds or more between two locks.
    for {_name, ticks} <- Enum.group_by(locks, &elem(&1, 1), &elem(&1, 0)) do
      for [a, b] <- Enum.chunk_every(ticks, 2, 1, :discard), do: assert(b - a >= 160)
    end

    # All the helpers: 4 seconds or more between two locks.
    for [{a, _}, {b, _}] <- Enum.chunk_every(locks, 2, 1, :discard), do: assert(b - a >= 40)
  end

  test "four helpers bring food from a pile across 12 rows in less than 5 minutes" do
    world = World.new(Sim.straight(12, helpers: 4, workers: 30))
    assert world.pile.width == 12

    {world, bridge_ticks} = Sim.run_until(world, 3000, &Sim.way_to_pile?/1)
    assert bridge_ticks != nil, "no bridge across 12 rows in 5 minutes"
    {world, food_ticks} = Sim.run_until(world, 3000 - bridge_ticks, &(&1.food_nest > 0))
    assert food_ticks != nil, "no food in 5 minutes"

    [record] = world.records
    assert record.rows == 12

    IO.puts(
      "\n  4 helpers, 12 rows: bridge after #{bridge_ticks / 10} s with #{record.bodies} bodies, " <>
        "first food after #{(bridge_ticks + food_ticks) / 10} s"
    )

    # One body wide stops at 7 rows: the helpers locked bodies beside bodies.
    assert record.bodies >= 19
    assert record.bodies <= 30
  end

  test "a helper takes the body of a worker after a lock, as a player does" do
    world = World.new(Sim.cfg(helpers: 1, workers: 10))
    {world, _} = Sim.run_until(world, 300, &(map_size(&1.locked) == 1))
    assert map_size(world.workers) == 9
    [helper] = helpers(world)
    assert helper.state == :alive
    assert helper.took != nil
  end

  test "helpers build with a player: a bridge has the names of the two" do
    {world, id} = World.join(World.new(Sim.cfg(helpers: 3, workers: 30)), "Ada")
    col = world.pile.col

    # The player locks the first body where the helpers start: at the cell of the near
    # bank that is nearest to the pile.
    start =
      Grid.forward(world.grid, Grid.cell(world.grid, 13, col))
      |> Enum.min_by(&Grid.distance(world.grid, &1, world.pile.cell))

    world = Sim.lock!(world, id, start)
    {world, ticks} = Sim.run_until(world, 900, &(&1.records != []))
    assert ticks != nil

    [record] = world.records
    names = Map.new(record.names, &{&1.name, &1})
    assert %{helper: false, bodies: 1} = names["Ada"]
    assert Enum.any?(record.names, & &1.helper)
  end
end
