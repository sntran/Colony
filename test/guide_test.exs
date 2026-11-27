defmodule Colony.GuideTest do
  @moduledoc "The guide: the one target that a player gets at each moment. Plan 0004, 4.6."

  use ExUnit.Case, async: true

  alias Colony.{Grid, Guide, Protocol, Sim, World}

  defp world(changes) do
    World.new(Sim.cfg(Keyword.merge([rivers: [{5, 5}, {9, 9}], carriers: 0], changes)))
  end

  # The number of steps on foot from a cell to each cell.
  defp steps(world, from), do: Sim.reach(world, from)

  test "rule 2: with a spare body and open cells, the nearest open cell by steps on foot" do
    {world, id} = World.join(world(spare: 10), "Ann")
    player = world.players[id]
    assert {:open, cell, stand, path} = Guide.target(world, player)
    assert World.open?(world, cell)
    assert cell in Grid.neighbors(world.grid, stand)
    assert length(path) == Map.fetch!(steps(world, player.cell), stand)

    # No other open cell has a stand cell with fewer steps.
    reach = steps(world, player.cell)

    least =
      for {open, _gain} <- world.open,
          to <- Grid.neighbors(world.grid, open),
          is_map_key(reach, to) do
        Map.fetch!(reach, to)
      end
      |> Enum.min()

    assert length(path) == least
  end

  test "rule 1: a player who carries food has the nest" do
    {world, id} = World.join(world(spare: 10), "Ann")
    player = %{world.players[id] | carry: %{pile: 1, units: 10}}
    assert Guide.target(world, player) == {:nest, world.nest}
  end

  test "rule 3: with no spare body, the nearest pile that the player can walk to" do
    {world, id} = World.join(world(spare: 5, carriers_per_crossing: 0), "Ann")
    world = Sim.cross!(world, id, 1)
    assert World.spare(world) == 0
    assert map_size(world.open) > 0
    assert {:pile, 1, cell} = Guide.target(world, world.players[id])
    assert cell == world.piles[1].cell
  end

  test "rule 4: nothing: no spare body and no pile that the player can walk to" do
    {world, id} = World.join(world(spare: 0), "Ann")
    assert map_size(world.open) > 0
    assert Guide.target(world, world.players[id]) == nil
  end

  test "share the work: after a lock, with fewer spare bodies than players, the pile comes first" do
    {world, ann} = World.join(world(spare: 7, carriers_per_crossing: 0), "Ann")
    {world, bob} = World.join(world, "Bob")
    world = Sim.cross!(world, ann, 1)
    # 2 spare bodies, 2 players: rule 2 comes first for both.
    assert World.spare(world) == 2
    assert {:open, _, _, _} = Guide.target(world, world.players[ann])

    # Ann locks: 1 spare body, 2 players. For Ann the pile comes first. Bob did not lock:
    # rule 2 comes first for Bob.
    world = Sim.lock!(world, ann, hd(Sim.open(world)))
    assert World.spare(world) == 1
    assert world.players[ann].last == :lock
    refute Guide.share?(world, world.players[bob])
    assert Guide.share?(world, world.players[ann])
    assert {:pile, 1, _} = Guide.target(world, world.players[ann])
    assert {:open, _, _, _} = Guide.target(world, world.players[bob])

    # Ann brings food: rule 2 comes first again.
    world = Sim.carry!(world, ann, 1)
    assert world.players[ann].last == :carry
    refute Guide.share?(world, world.players[ann])
    assert {:open, _, _, _} = Guide.target(world, world.players[ann])
  end

  test "a player alone always has rule 2 first" do
    {world, id} = World.join(world(spare: 6, carriers_per_crossing: 0), "Ann")
    world = Sim.cross!(world, id, 1)
    assert World.spare(world) == 1
    assert world.players[id].last == :lock
    refute Guide.share?(world, world.players[id])
    assert {:open, _, _, _} = Guide.target(world, world.players[id])
  end

  @tag :tmp_dir
  test "the page shows the same guide as the server", %{tmp_dir: dir} do
    node = System.find_executable("node")

    if node == nil do
      IO.puts("\n  no Node.js: the test of the guide of the page does not run")
    else
      {world, ann} = World.join(world(spare: 7, carriers_per_crossing: 0, seed: 5), "Ann")
      {world, _bob} = World.join(world, "Bob")
      world = Sim.cross!(world, ann, 1)
      world = Sim.lock!(world, ann, hd(Sim.open(world)))
      file = Path.join(dir, "snapshot.bin")
      File.write!(file, Protocol.snapshot(world, ann))

      # Bodies in many cells, with and without food, after a lock and after food.
      cells =
        world.grid.count
        |> then(&(0..(&1 - 1)))
        |> Enum.filter(&World.walkable?(world, &1))
        |> Enum.take_every(37)

      cases =
        for cell <- cells, {carry, last} <- [{false, nil}, {false, :lock}, {true, nil}] do
          {x, z} = Grid.center(world.grid, cell)
          %{x: x, z: z, cell: cell, carry: carry, last: last}
        end

      json = cases |> Enum.map(&Map.take(&1, [:x, :z, :carry, :last])) |> JSON.encode!()
      {out, 0} = System.cmd(node, ["test/js/guide.mjs", file, json])
      page = JSON.decode!(out)

      server =
        for c <- cases do
          player = %{
            world.players[ann]
            | x: c.x,
              z: c.z,
              cell: c.cell,
              carry: if(c.carry, do: %{pile: 1, units: 10}),
              last: c.last
          }

          case Guide.target(world, player) do
            nil -> nil
            {:nest, cell} -> %{"kind" => "nest", "cell" => cell}
            {:open, cell, _, _} -> %{"kind" => "open", "cell" => cell}
            {:pile, _id, cell} -> %{"kind" => "pile", "cell" => cell}
          end
        end

      kinds = page |> Enum.reject(&is_nil/1) |> Enum.map(& &1["kind"]) |> Enum.frequencies()

      IO.puts(
        "\n  the guide of the page and of the server for #{length(cases)} bodies: #{inspect(kinds)}"
      )

      different =
        for {a, b, c} <- Enum.zip([page, server, cases]),
            a != b,
            do: {c.cell, c.carry, c.last, a, b}

      assert different == []
      assert Map.keys(kinds) |> Enum.sort() == ["nest", "open", "pile"]
    end
  end
end
