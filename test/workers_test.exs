defmodule Colony.WorkersTest do
  @moduledoc "Tests 3 and 4 of the plan: the workers build a bridge, bring food and let go."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Sim, World}

  # 5 minutes of world time.
  @five_minutes 3000

  defp complete?(world), do: is_map_key(world.walk, world.grid.food)

  test "200 workers with scent complete a bridge and bring food in less than 5 minutes" do
    world = World.new(Sim.cfg(workers: 200)) |> World.set_demo(true)

    {world, bridge_ticks} = Sim.run_until(world, @five_minutes, &complete?/1)
    assert bridge_ticks != nil, "no complete bridge in 5 minutes"

    {world, food_ticks} = Sim.run_until(world, @five_minutes - bridge_ticks, &(&1.food_nest > 0))
    assert food_ticks != nil, "no food at the nest in 5 minutes"

    IO.puts(
      "\n  200 workers: bridge complete after #{bridge_ticks / 10} s with " <>
        "#{length(Sim.locked_workers(world))} bodies, first food at the nest after " <>
        "#{(bridge_ticks + food_ticks) / 10} s of world time"
    )

    # The bridge goes from bank to bank and each body has support.
    rows = world.locked |> Map.keys() |> Enum.map(&Grid.row(world.grid, &1)) |> Enum.uniq()
    assert Enum.sort(rows) == Enum.to_list(14..25)
    assert Enum.all?(world.supports, fn {_cell, support} -> support > 0 end)

    # The number of workers stays the same.
    world = Sim.run(world, 600)
    assert map_size(world.workers) + length(Sim.locked_workers(world)) == 200

    assert world.food_nest + world.food_pile + Enum.count(world.workers, fn {_, w} -> w.carry end) ==
             500
  end

  test "workers with no scent stay near the nest and do not lock" do
    world = World.new(Sim.cfg(workers: 200)) |> Sim.run(600)
    assert world.locked == %{}

    for {_id, worker} <- world.workers do
      assert Grid.nest_distance(world.grid, worker.cell) <= 6
    end
  end

  test "when the scent goes away, all locked workers let go and the bodies of players stay if they have support" do
    cfg = Sim.cfg(workers: 200, food_units: 30, food_refill_seconds: nil)
    {world, id} = World.join(World.new(cfg), "Ada")

    # Three bodies of a player, far from the bridge of the workers. They have support
    # from the bank.
    own = for n <- 1..3, do: Sim.gap_cell(world, n, 10)
    world = Enum.reduce(own, world, &Sim.lock!(&2, id, &1))

    # The workers build a bridge and carry all the food.
    world = World.set_demo(world, true)
    {world, ticks} = Sim.run_until(world, @five_minutes, &(&1.food_nest == 30))
    assert ticks != nil
    assert Sim.locked_workers(world) != []

    # One body of the player on the bridge of the workers, in the middle of the gap.
    # Only the workers give it support.
    middle =
      Enum.find(world.frontier, fn cell ->
        Grid.row(world.grid, cell) in 18..21 and
          Enum.any?(Grid.neighbors(world.grid, cell), &(world.locked[&1][:kind] == :worker))
      end)

    world = Sim.lock!(world, id, middle)
    assert world.locked[middle].kind == :player

    # The scent goes away.
    world = World.set_demo(world, false)
    {world, ticks} = Sim.run_until(world, @five_minutes, &(&1.scent == %{}))
    assert ticks != nil, "the scent did not go away"

    # 20 seconds is the time to let go. Some bodies are used a short time after the scent
    # is gone, thus the test waits longer.
    world = Sim.run(world, 600)

    assert Sim.locked_workers(world) == []
    assert map_size(world.workers) == 200
    assert Enum.sort(Map.keys(world.locked)) == Enum.sort(own)
    assert Enum.map(own, &world.supports[&1]) == [7.0, 6.0, 5.0]
    refute is_map_key(world.locked, middle)
  end

  test "workers help with a bridge of a player that has scent on it" do
    {world, id} = World.join(World.new(Sim.cfg(workers: 200, seed: 5)), "Ada")
    col = 30

    # The player locks one body, then makes a line of scent from the nest to the gap.
    world = Sim.lock!(world, id, Sim.gap_cell(world, 1, col))

    world =
      Enum.reduce(7..13, world, fn row, world ->
        cell = Grid.cell(world.grid, row, col)
        world = Sim.walk(world, id, cell)
        World.put_scent(world, cell, 100)
      end)

    {world, ticks} = Sim.run_until(world, 1000, &complete?/1)
    assert ticks != nil
    assert world.locked[Sim.gap_cell(world, 1, col)].name == "Ada"
  end
end
