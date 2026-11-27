defmodule Colony.StopTest do
  @moduledoc """
  The world stops when no person is there: plan 0004, 4.4. A page that only looks is not a
  person. The server saves the world when the last person goes.
  """

  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Colony.{Server, Store, World}

  @endpoint ColonyWeb.Endpoint

  setup do
    dir = Path.join(System.tmp_dir!(), "colony-stop-#{System.unique_integer([:positive])}")
    game = Application.fetch_env!(:colony, :game)
    path = Path.join(dir, "world.bin")

    Application.put_env(
      :colony,
      :game,
      Keyword.merge(game, save_file: path, seed: 1, carriers: 12, spare: 10)
    )

    on_exit(fn ->
      Application.put_env(:colony, :game, game)
      File.rm_rf!(dir)
    end)

    start_supervised!(Server)
    %{path: path}
  end

  defp world, do: :sys.get_state(Server).world

  # The parts of the world that change when the world moves.
  defp moving(world) do
    {world.tick, world.piles[1].units, Enum.map(world.workers, fn {id, w} -> {id, w.cell} end)}
  end

  test "with no person, the world does not change; with a page that only looks, the same", %{
    path: path
  } do
    before = moving(world())
    Process.sleep(2500)
    assert moving(world()) == before

    {:ok, _reply, look} =
      subscribe_and_join(socket(ColonyWeb.UserSocket), "world", %{"look" => true})

    assert_push("s", {:binary, _snapshot})
    Process.sleep(2500)
    assert moving(world()) == before
    assert World.persons(world()) == 0

    # A person joins: the world moves.
    {:ok, _reply, person} =
      subscribe_and_join(socket(ColonyWeb.UserSocket), "world", %{"name" => "Ada"})

    Process.sleep(1500)
    {tick, units, _workers} = moving(world())
    assert tick >= elem(before, 0) + 10
    assert units < elem(before, 1)

    # The person goes: the world stops, and the server saves it.
    File.rm(path)
    Process.unlink(person.channel_pid)
    ref = Process.monitor(person.channel_pid)
    GenServer.stop(person.channel_pid, :shutdown)
    assert_receive {:DOWN, ^ref, _, _, _}
    Process.sleep(500)
    stopped = moving(world())
    assert World.persons(world()) == 0
    assert {:ok, saved} = Store.load(path, World.save_version())
    assert saved.piles[1].units == elem(stopped, 1)
    Process.sleep(2000)
    assert moving(world()) == stopped
    assert Process.alive?(look.channel_pid)
  end
end
