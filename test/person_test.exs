defmodule Colony.PersonTest do
  @moduledoc """
  A player is the same person for always: plan 0004, section 4.11. Automatic tests 9 and 10.
  """

  use ExUnit.Case, async: true

  alias Colony.{Sim, Store, World}

  @secret "a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6"

  defp world(changes \\ []) do
    World.new(Sim.cfg(Keyword.merge([spare: 40, rivers: [{5, 5}, {6, 6}]], changes)))
  end

  # The player locks `count` bodies into open cells.
  defp locks(world, id, count) do
    Enum.reduce(1..count//1, world, fn _, world -> Sim.lock!(world, id, hd(Sim.open(world))) end)
  end

  describe "automatic test 9" do
    test "a new name changes all the bodies of the player, the records and the story" do
      {world, ann} = World.join(world(), "Ann", @secret)
      {world, bob} = World.join(world, "Bob")
      world = Sim.cross!(world, ann, 1)
      world = locks(world, bob, 1)
      world = locks(world, ann, 2)
      person = world.players[ann].person
      bodies = for {_cell, %{owner: ^person}} <- world.locked, do: 1

      world = World.rename(world, ann, "Ann Two")
      {world, events} = World.tick(world)
      # The changed records go to the clients one time each second.
      {world, later} =
        Enum.reduce(1..10, {world, []}, fn _, {world, records} ->
          {world, events} = World.tick(world)
          {world, records ++ events.records}
        end)

      assert for({_cell, %{owner: ^person, name: name}} <- world.locked, do: name) ==
               List.duplicate("Ann Two", length(bodies))

      assert world.people[person].name == "Ann Two"
      assert world.players[ann].name == "Ann Two"
      # The bodies of Bob keep the name of Bob.
      assert Enum.any?(world.locked, fn {_cell, body} -> body.name == "Bob" end)
      # The clients get the new name of the person and the record again.
      assert {person, "Ann Two"} in events.people
      assert [%{id: 1, names: names}] = later
      assert %{name: "Ann Two", owner: ^person} = Enum.find(names, &(&1.owner == person))
      assert Enum.any?(World.story(world).names, &(&1.name == "Ann Two"))
      refute Enum.any?(World.story(world).names, &(&1.name == "Ann"))
    end

    test "a second join with the same secret number is the same person" do
      {world, ann} = World.join(world(), "Ann", @secret)
      world = Sim.cross!(world, ann, 1)
      person = world.players[ann].person
      before = World.person_numbers(world, person)
      assert before.bodies > 0
      world = World.leave(world, ann)

      # The same secret number with a new name: the same person, and all the bodies get the
      # new name.
      {world, again} = World.join(world, "Ann Three", @secret)
      assert world.players[again].person == person
      assert World.person_numbers(world, person) == %{before | name: "Ann Three"}
      assert Enum.all?(world.locked, fn {_cell, body} -> body.name == "Ann Three" end)

      # Another secret number, or no secret number: a new person.
      {world, other} = World.join(world, "Ann Three", String.reverse(@secret))
      {world, none} = World.join(world, "Ann Three")
      people = [person, world.players[other].person, world.players[none].person]
      assert length(Enum.uniq(people)) == 3
      assert World.person_numbers(world, world.players[none].person).bodies == 0
    end

    test "the server keeps only the SHA-256 of the secret number" do
      {world, ann} = World.join(world(), "Ann", @secret)
      entry = world.people[world.players[ann].person]
      assert entry.secret == :crypto.hash(:sha256, @secret)
      refute inspect(World.to_save(world)) =~ @secret
    end
  end

  describe "automatic test 10" do
    @tag :tmp_dir
    test "save and load keep the nest, the old nests, the two kinds of workers, the players and their numbers",
         %{tmp_dir: dir} do
      cfg = Sim.cfg(spare: 40, carriers: 12, rivers: [{5, 5}, {6, 6}])
      {world, ann} = World.join(World.new(cfg), "Ann", @secret)
      world = Sim.cross!(world, ann, 1)
      world = Sim.carry!(world, ann, 1)
      world = Sim.cross!(world, ann, 2)
      # Workers walk on the bodies.
      world = Sim.run(world, 300)
      person = world.players[ann].person
      numbers = World.person_numbers(world, person)
      assert numbers.food == 10 and numbers.walks > 0

      path = Path.join(dir, "world.bin")
      :ok = Store.save(path, World.to_save(world))
      {:ok, saved} = Store.load(path, World.save_version())
      again = World.new(cfg, saved)

      assert again.nest == world.nest
      assert again.old_nests == world.old_nests
      assert length(again.old_nests) == 2
      assert World.carriers(again) == World.carriers(world)
      assert World.spare(again) == World.spare(world)
      assert again.people == world.people
      assert World.person_numbers(again, person) == numbers

      # On a later day, the page joins with the same secret number: the same numbers.
      {again, id} = World.join(again, "Ann", @secret)
      assert again.players[id].person == person
      assert World.person_numbers(again, person) == numbers
    end
  end
end
