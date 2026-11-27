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
      carriers: 12,
      spare: Map.get(context, :spare, 10)
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

  # Goes to the edge of land 0 in the column of pile 1, then to the river. Returns the
  # cell of the river after it: the first body of a bridge locks 6 columns or less from
  # the column of the pile.
  defp move_to_river(socket) do
    world = :sys.get_state(Colony.Server).world
    col = world.piles[1].col
    step = Colony.Grid.row_step()
    {nest_row, nest_col} = {div(world.nest, 60), rem(world.nest, 60)}
    x = fn row, c -> c + 0.5 * rem(row, 2) end

    # Along the row of the nest to the column of the pile, then to the north.
    way =
      for(c <- nest_col..col//if(col >= nest_col, do: 1, else: -1), do: {x.(nest_row, c), nest_row}) ++
        for row <- (nest_row + 1)..13, do: {x.(row, col), row}

    for {x, row} <- way do
      # The speed permits one cell each 3 ticks.
      Process.sleep(320)
      push(socket, "m", {:binary, Colony.Protocol.encode_move(x, row * step, 0.0)})
    end

    Process.sleep(150)
    14 * 60 + col
  end

  test "the snapshot is binary and has the number of the player", %{snapshot: snapshot} do
    rows = :sys.get_state(Colony.Server).world.grid.rows
    assert <<_tick::32, 1, 1::16-little, 60::16-little, ^rows::16-little, _rest::binary>> = snapshot
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

    # A spare body can walk on the new body at once: the count of walks can be more than 0.
    ref = push(socket, "body", %{"cell" => cell})
    assert_reply(ref, :ok, %{name: "Ada", helper: false, crossings: crossings, time: time})
    assert is_integer(time) and is_integer(crossings)

    ref = push(socket, "body", %{"cell" => cell + 1})
    assert_reply(ref, :error)

    # The story has the name of the player and the body.
    ref = push(socket, "story", %{})

    assert_reply(ref, :ok, %{
      names: [%{name: "Ada", helper: false, bodies: 1, food: 0}],
      crossings: 0
    })
  end

  test "a player gets a new name: all the bodies of the person get it", %{socket: socket} do
    cell = move_to_river(socket)
    ref = push(socket, "lock", %{"cell" => cell})
    assert_reply(ref, :ok, %{worker: _}, 1000)

    ref = push(socket, "name", %{"name" => "Brisk <b>Fern</b> 12"})
    assert_reply(ref, :ok)
    ref = push(socket, "name", %{"name" => 5})
    assert_reply(ref, :error)

    # The name is plain text of 16 characters or fewer.
    ref = push(socket, "body", %{"cell" => cell})
    assert_reply(ref, :ok, %{name: "Brisk bFernb 12"})
    assert %{players: 1} = Colony.Server.stats()
    ref = push(socket, "story", %{})
    assert_reply(ref, :ok, %{names: [%{name: "Brisk bFernb 12", bodies: 1}]})
    world = :sys.get_state(Colony.Server).world
    assert [%{name: "Brisk bFernb 12"}] = Map.values(world.players)

    # The panel of the name: the numbers of the person.
    ref = push(socket, "me", %{})
    assert_reply(ref, :ok, %{name: "Brisk bFernb 12", bodies: 1, food: 0, walks: walks})
    assert is_integer(walks)
  end

  @tag spare: 0
  test "with no spare body, the lock gets the reply error", %{socket: socket} do
    cell = move_to_river(socket)
    ref = push(socket, "lock", %{"cell" => cell})
    assert_reply(ref, :error, _, 1000)
    # A cell that is not open also gets the reply error.
    ref = push(socket, "lock", %{"cell" => cell + 60})
    assert_reply(ref, :error, _, 1000)
  end

  test "a client that only looks gets the world and no body" do
    {:ok, _reply, socket} =
      subscribe_and_join(socket(ColonyWeb.UserSocket), "world", %{"look" => true})

    assert_push(
      "s",
      {:binary,
       <<_tick::32, 1, 1::16-little, 60::16-little, _rows::16-little, _seed::32, 0xFFFF::16-little,
         0::16-little, _rest::binary>>}
    )

    ref = push(socket, "lock", %{"cell" => 870})
    assert_reply(ref, :error)
    # The world has one player: the player of the setup.
    assert Colony.Server.stats().players == 1
  end
end
