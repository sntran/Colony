defmodule Colony.SaveTest do
  @moduledoc "Test 5 of the plan: save and load give the same world."

  use ExUnit.Case, async: true

  alias Colony.{Sim, Store, World}

  @tag :tmp_dir
  test "save and load give the same world", %{tmp_dir: dir} do
    cfg = Sim.cfg(workers: 200, seed: 77)
    {world, id} = World.join(World.new(cfg), "Bình")

    # A world with bodies of a player, bodies of workers, scent and food at the nest.
    world = Enum.reduce(1..3, world, fn n, world -> Sim.lock!(world, id, Sim.gap_cell(world, n, 12)) end)
    world = world |> World.set_demo(true) |> Sim.run(400)
    assert Sim.locked_workers(world) != []
    assert world.scent != %{}
    assert world.food_nest > 0

    path = Path.join(dir, "world.bin")
    saved = World.to_save(world)
    :ok = Store.save(path, saved)
    {:ok, loaded} = Store.load(path)
    assert loaded == saved

    again = World.new(cfg, loaded)
    assert World.to_save(again) == saved
    assert again.seed == world.seed
    assert again.supports == world.supports
    assert again.frontier |> Enum.sort() == elem(World.take_events(World.flag(world, :structure)), 0).frontier |> Enum.sort()
    assert again.food_pile == world.food_pile
    assert again.food_nest == world.food_nest

    # The names and the times of the bodies of the player are there.
    for n <- 1..3 do
      cell = Sim.gap_cell(world, n, 12)
      assert again.locked[cell].name == "Bình"
      assert again.locked[cell].time == world.locked[cell].time
    end

    # The number of workers is the same: the locked workers are locked, the others are free.
    assert map_size(again.workers) + length(Sim.locked_workers(again)) == 200
  end

  @tag :tmp_dir
  test "reset deletes the file, and a world with no file is new", %{tmp_dir: dir} do
    path = Path.join(dir, "world.bin")
    assert Store.load(path) == :none
    :ok = Store.save(path, World.to_save(World.new(Sim.cfg())))
    assert {:ok, _} = Store.load(path)
    assert Store.reset(path) == :deleted
    assert Store.reset(path) == :none
    assert Store.load(path) == :none
  end

  @tag :tmp_dir
  test "a file that is not a save file gives a new world", %{tmp_dir: dir} do
    path = Path.join(dir, "world.bin")
    File.write!(path, "not a save file")

    ExUnit.CaptureLog.capture_log(fn ->
      assert Store.load(path) == :none
    end)
  end
end
