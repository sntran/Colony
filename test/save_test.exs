defmodule Colony.SaveTest do
  @moduledoc "Save and load keep the world: the lands, the bodies, the piles, the records and the story."

  use ExUnit.Case, async: true

  alias Colony.{Sim, Store, World}

  # A world with two bridges of helpers and of a player, records, scent and food.
  defp played do
    cfg = Sim.cfg(helpers: 3, spare: 30, seed: 77, helper_lock_seconds: 6)
    {world, id} = World.join(World.new(Keyword.merge(cfg, helpers: 0)), "Bình")
    world = Sim.lock!(world, id, Sim.river_cell(world, 1, world.piles[1].col))
    world = World.set_helpers(world, 3)
    {world, ticks} = Sim.run_until(world, 6000, &(&1.stage == 3 and &1.food_nest > 20))
    true = ticks != nil
    {cfg, world}
  end

  @tag :tmp_dir
  test "save and load give the same world", %{tmp_dir: dir} do
    {cfg, world} = played()
    assert [%{id: 2}, %{id: 1}] = world.records
    assert world.scent != %{}

    path = Path.join(dir, "world.bin")
    saved = World.to_save(world)
    :ok = Store.save(path, saved)
    {:ok, loaded} = Store.load(path, World.save_version())
    assert loaded == saved

    again = World.new(Keyword.merge(cfg, helpers: 0), loaded)
    assert World.to_save(again) == saved
    assert again.seed == world.seed
    # The lands and the rivers.
    assert again.grid == world.grid
    assert again.supports == world.supports
    assert again.piles == world.piles
    assert again.stage == world.stage
    assert again.open == world.open
    assert again.food_nest == world.food_nest
    assert map_size(again.workers) == map_size(world.workers)

    # The records, the story and the counts of the bodies are there.
    assert again.records == world.records
    assert hd(again.records).names != []
    assert Map.delete(World.story(again), :time) == Map.delete(World.story(world), :time)
    assert length(World.story(again).locks) == map_size(world.locked)

    for {cell, body} <- world.locked, do: assert(again.locked[cell] == body)
    assert Enum.any?(again.locked, fn {_cell, body} -> body.crossings > 0 end)
    assert Enum.any?(again.locked, fn {_cell, body} -> body.name == "Bình" and not body.helper end)

    # The world continues after the load: the next lock is the next lock of the story.
    again = World.set_helpers(again, 3)
    {again, ticks} = Sim.run_until(again, 600, &(map_size(&1.locked) > map_size(world.locked)))
    assert ticks != nil
    assert List.last(World.story(again).locks).n == world.lock_count + 1
  end

  @tag :tmp_dir
  test "a long world keeps all its rivers after a load", %{tmp_dir: dir} do
    cfg = Sim.cfg(spare: 60, rivers: [{5, 5}, {6, 6}])
    {world, id} = World.join(World.new(cfg), "Tester")
    world = Enum.reduce(1..4, world, &Sim.cross!(&2, id, &1))
    # Pile 5 and two rivers after it.
    assert World.rivers(world) == 7
    assert world.stage == 5

    path = Path.join(dir, "world.bin")
    :ok = Store.save(path, World.to_save(world))
    {:ok, loaded} = Store.load(path, World.save_version())
    again = World.new(cfg, loaded)
    assert again.grid == world.grid
    assert again.stage == 5
    assert again.open == world.open
    assert again.nest == world.nest
    assert again.old_nests == world.old_nests
    assert again.piles == world.piles
    assert map_size(again.locked) == map_size(world.locked)
  end

  test "the store knows each atom of a save file" do
    # If an atom is not in the list of the store, a server that starts cannot read the file.
    {_cfg, world} = played()
    atoms = collect_atoms(World.to_save(world), MapSet.new())
    assert MapSet.subset?(atoms, MapSet.new(Store.atoms()))
  end

  defp collect_atoms(term, found) when is_atom(term), do: MapSet.put(found, term)
  defp collect_atoms(term, found) when is_list(term), do: Enum.reduce(term, found, &collect_atoms/2)
  defp collect_atoms(term, found) when is_tuple(term), do: collect_atoms(Tuple.to_list(term), found)
  defp collect_atoms(term, found) when is_map(term), do: collect_atoms(Map.to_list(term), found)
  defp collect_atoms(_term, found), do: found

  @tag :tmp_dir
  test "reset deletes the file, and a world with no file is new", %{tmp_dir: dir} do
    path = Path.join(dir, "world.bin")
    assert Store.load(path, World.save_version()) == :none
    :ok = Store.save(path, World.to_save(World.new(Sim.cfg())))
    assert {:ok, _} = Store.load(path, World.save_version())
    assert Store.reset(path) == :deleted
    assert Store.reset(path) == :none
    assert Store.load(path) == :none
  end

  @tag :tmp_dir
  test "a file that is not a save file gives a new world", %{tmp_dir: dir} do
    path = Path.join(dir, "world.bin")
    File.write!(path, "not a save file")

    ExUnit.CaptureLog.capture_log(fn ->
      assert Store.load(path, World.save_version()) == :none
    end)
  end

  @tag :tmp_dir
  test "a save file of plan 0002 is not loaded: it gets a new name", %{tmp_dir: dir} do
    path = Path.join(dir, "world.bin")

    old = %{
      version: 2,
      seed: 5,
      locked: [{870, "Old", false, 100, 3}],
      scent: %{},
      pile: nil,
      history: %{},
      food_nest: 3,
      food_credit: 0,
      spare: 12,
      records: []
    }

    :ok = Store.save(path, old)
    assert Store.load(path, World.save_version()) == {:old, path <> ".v2"}
    refute File.exists?(path)
    # The old file is there with its new name, and it did not change.
    assert Store.load(path <> ".v2") == {:ok, old}
    # The next start finds no file: a new world.
    assert Store.load(path, World.save_version()) == :none
  end
end
