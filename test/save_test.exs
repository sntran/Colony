defmodule Colony.SaveTest do
  @moduledoc "Save and load keep the world: the bodies with their counts, the pile and the records."

  use ExUnit.Case, async: true

  alias Colony.{Sim, Store, World}

  # A world with a bridge of helpers and of a player, a record, scent and food.
  defp played do
    cfg = Sim.cfg(helpers: 3, workers: 30, seed: 77, pile_units: 60)
    {world, id} = World.join(World.new(cfg), "Bình")
    world = Sim.lock!(world, id, Sim.river_cell(world, 1, 12))
    {world, ticks} = Sim.run_until(world, 3000, &(&1.pile.id == 2 and &1.food_nest > 20))
    true = ticks != nil
    {cfg, world}
  end

  @tag :tmp_dir
  test "save and load give the same world", %{tmp_dir: dir} do
    {cfg, world} = played()
    assert [%{id: 1, done: _}] = world.records
    assert world.scent != %{}

    path = Path.join(dir, "world.bin")
    saved = World.to_save(world)
    :ok = Store.save(path, saved)
    {:ok, loaded} = Store.load(path)
    assert loaded == saved

    again = World.new(Keyword.merge(cfg, helpers: 0), loaded)
    assert World.to_save(again) == saved
    assert again.seed == world.seed
    assert again.grid.river == world.grid.river
    assert again.supports == world.supports
    assert again.pile == world.pile
    assert again.food_nest == world.food_nest
    assert map_size(again.workers) == map_size(world.workers)

    # The records and the counts of the bodies are there.
    assert again.records == world.records
    assert hd(again.records).names != []

    for {cell, body} <- world.locked do
      assert again.locked[cell].name == body.name
      assert again.locked[cell].time == body.time
      assert again.locked[cell].crossings == body.crossings
    end

    assert Enum.any?(again.locked, fn {_cell, body} -> body.crossings > 0 end)
    assert Enum.any?(again.locked, fn {_cell, body} -> body.name == "Bình" and not body.helper end)

    # The world continues after the load: the carriers of the new workers bring food.
    assert Sim.run(World.set_helpers(again, 3), 300).tick == 300
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

  test "a save file of plan 0001 gives a new world" do
    old = %{version: 1, seed: 5, locked: [], scent: %{}, food_pile: 500, food_nest: 3}
    world = World.new(Sim.cfg(), old)
    assert world.seed == 5
    assert world.locked == %{}
    assert world.pile.id == 1
    assert world.food_nest == 0
  end
end
