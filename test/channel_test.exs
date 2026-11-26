defmodule ColonyWeb.ChannelTest do
  @moduledoc "The channel of a player. A message with wrong data must not stop a channel."

  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  @endpoint ColonyWeb.Endpoint

  setup context do
    # A server with a world that the test does not keep.
    dir = Path.join(System.tmp_dir!(), "colony-channel-#{System.unique_integer([:positive])}")
    game = Application.fetch_env!(:colony, :game)

    changes = [
      save_file: Path.join(dir, "world.bin"),
      seed: 1,
      workers: Map.get(context, :workers, 30)
    ]

    Application.put_env(:colony, :game, Keyword.merge(game, changes))

    on_exit(fn ->
      Application.put_env(:colony, :game, game)
      File.rm_rf!(dir)
    end)

    start_supervised!(Colony.Server)

    {:ok, _reply, socket} =
      subscribe_and_join(socket(ColonyWeb.UserSocket), "world", %{"name" => "Ada"})

    assert_push("s", {:binary, snapshot})
    assert_push("records", %{records: []})
    %{socket: socket, snapshot: snapshot}
  end

  # The cell of the edge of the near bank, in the column of the nest, and the river cell after it.
  defp move_to_river(socket) do
    position = fn row ->
      Colony.Protocol.encode_move(30 + 0.5 * rem(row, 2), row * Colony.Grid.row_step(), 0.0, false)
    end

    for row <- 7..13 do
      # The speed permits one cell each 3 ticks.
      Process.sleep(320)
      push(socket, "m", {:binary, position.(row)})
    end

    Process.sleep(150)
    14 * 60 + 30
  end

  test "the snapshot is binary and has the number of the player", %{snapshot: snapshot} do
    assert <<_tick::32, 1, 1::16-little, 60::16-little, _rest::binary>> = snapshot
  end

  test "a lock with an `at` value that is not text does not stop the channel", %{socket: socket} do
    for at <- [5, %{"x" => 1}, [1, 2], true, nil, "not base64 !!", ""] do
      ref = push(socket, "lock", %{"cell" => 870, "at" => at})
      assert_reply(ref, :error)
    end

    ref = push(socket, "ping", %{})
    assert_reply(ref, :ok)
    assert Process.alive?(socket.channel_pid)
  end

  test "messages with wrong data do not stop the channel", %{socket: socket} do
    for {event, payload} <- [
          {"lock", %{}},
          {"lock", %{"cell" => "870"}},
          {"lock", %{"cell" => -1}},
          {"lock", %{"cell" => 99_999_999}},
          {"lock", "text"},
          {"body", %{"cell" => "x"}},
          {"body", %{}},
          {"body", %{"cell" => 99_999_999}}
        ] do
      ref = push(socket, event, payload)
      assert_reply(ref, :error)
    end

    # These messages get no reply.
    push(socket, "m", %{"x" => 1})
    push(socket, "m", {:binary, <<1, 2, 3>>})
    push(socket, "m", {:binary, :binary.copy(<<255>>, 6)})
    push(socket, "no such event", %{"a" => 1})
    push(socket, "ping", "text")

    ref = push(socket, "ping", %{})
    assert_reply(ref, :ok)
    assert Process.alive?(socket.channel_pid)
  end

  test "a lock gives the new body of the player, and a tap gives the data of a body", %{
    socket: socket
  } do
    cell = move_to_river(socket)
    ref = push(socket, "lock", %{"cell" => cell})
    # The colony has free workers: the new body is the body of a worker.
    assert_reply(ref, :ok, %{x: x, z: z, worker: worker}, 1000)
    assert is_float(x) and is_float(z) and is_integer(worker)

    ref = push(socket, "body", %{"cell" => cell})
    assert_reply(ref, :ok, %{name: "Ada", helper: false, crossings: 0, time: time})
    assert is_integer(time)

    ref = push(socket, "body", %{"cell" => cell + 1})
    assert_reply(ref, :error)
  end

  @tag workers: 0
  test "with no free worker, the lock tells the seconds to the new body", %{socket: socket} do
    cell = move_to_river(socket)
    ref = push(socket, "lock", %{"cell" => cell})
    assert_reply(ref, :ok, %{wait: 3}, 1000)
    assert_push("you", %{state: "alive"}, 4000)
  end
end
