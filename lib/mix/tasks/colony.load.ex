defmodule Mix.Tasks.Colony.Load do
  @shortdoc "Runs the load test: a world of 20 rivers, 20 clients and 8 helpers for 5 minutes"

  @moduledoc """
  Runs the load test of plan 0004, section 5.2, with the targets of plan 0001.

      mix colony.load [--seconds 300] [--rivers 20] [--locked 2000] [--carriers 150]
                      [--spare 200] [--clients 20] [--helpers 8] [--port 4010]

  The task makes a long world first: the colony crosses `rivers` rivers, and it has
  `locked` locked bodies or more. The locks of this world go fast, with no walk. Then the
  task starts the server with this world, with `carriers` carriers and `spare` spare
  bodies, in a file that is not the usual file. The helpers build the next bridge, and
  the carriers carry food.
  Each client is a real WebSocket connection. It joins the channel as a player, moves
  10 times each second near the nest, and counts the bytes that it gets.

  At the end the task prints the tick time (median, 95th and 99th percentile), the memory,
  and the bytes each second for each client.
  """

  use Mix.Task

  alias Colony.{Grid, Protocol, Server, Store, World}

  @impl true
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          seconds: :integer,
          rivers: :integer,
          locked: :integer,
          carriers: :integer,
          spare: :integer,
          clients: :integer,
          helpers: :integer,
          port: :integer
        ]
      )

    seconds = opts[:seconds] || 300
    rivers = opts[:rivers] || 20
    locked = opts[:locked] || 2000
    carriers = opts[:carriers] || 150
    spare = opts[:spare] || 200
    clients = opts[:clients] || 20
    helpers = opts[:helpers] || 8
    port = opts[:port] || 4010

    Mix.Task.run("app.config")

    save_file =
      Path.join(System.tmp_dir!(), "colony-load-#{System.unique_integer([:positive])}.bin")

    game =
      :colony
      |> Application.fetch_env!(:game)
      |> Keyword.merge(
        carriers_max: max(carriers, 150),
        spare_max: max(spare, 200),
        helpers: helpers,
        save_file: save_file,
        seed: 2027
      )

    Application.put_env(:colony, :game, game)
    Mix.shell().info("Making a world of #{rivers} crossings and #{locked} locked bodies or more.")
    world = long_world(game, rivers, locked)
    :ok = Store.save(save_file, %{World.to_save(world) | workers: %{carrier: carriers, spare: spare}})

    endpoint =
      :colony
      |> Application.get_env(ColonyWeb.Endpoint, [])
      |> Keyword.merge(http: [ip: {127, 0, 0, 1}, port: port], server: true)

    Application.put_env(:colony, ColonyWeb.Endpoint, endpoint)
    Logger.configure(level: :warning)
    Mix.Task.run("app.start")

    rate = Keyword.fetch!(game, :tick_rate)
    world = :sys.get_state(Server).world
    nest = Grid.center(world.grid, world.nest)

    Mix.shell().info(
      "Load test: #{World.rivers(world)} rivers in the grid, #{world.stage - 1} crossings, " <>
        "#{map_size(world.locked)} locked bodies, #{World.carriers(world)} carriers, " <>
        "#{World.spare(world)} spare bodies, #{clients} clients, #{helpers} helpers, #{seconds} s, " <>
        "#{rate} ticks each second."
    )

    parent = self()

    pids =
      for n <- 1..clients do
        spawn_link(fn -> client(parent, n, port, nest, seconds) end)
      end

    # The first seconds are the start of the clients. They are not in the result.
    Process.sleep(3000)
    Server.stats(reset: true)
    for pid <- pids, do: send(pid, :reset)
    started = System.monotonic_time(:millisecond)

    memory = sample_memory(started + seconds * 1000, [])
    stats = Server.stats()
    elapsed = (System.monotonic_time(:millisecond) - started) / 1000

    for pid <- pids, do: send(pid, :report)

    reports =
      for _ <- pids do
        receive do
          {:report, report} -> report
        after
          10_000 -> Mix.raise("A client did not answer.")
        end
      end

    File.rm(save_file)
    print(stats, memory, reports, elapsed, rate)
  end

  defp sample_memory(until, samples) do
    sample = :erlang.memory(:total)
    left = until - System.monotonic_time(:millisecond)

    if left <= 0 do
      [sample | samples]
    else
      Process.sleep(min(left, 5000))
      sample_memory(until, [sample | samples])
    end
  end

  defp print(stats, memory, reports, elapsed, rate) do
    times = stats.tick_times
    count = length(times)
    percentile = fn p -> Enum.at(times, min(count - 1, round(p * (count - 1)))) / 1000 end
    megabytes = fn bytes -> Float.round(bytes / 1_048_576, 1) end
    rates = Enum.map(reports, &(&1.bytes / elapsed))
    ticks = Enum.map(reports, &(&1.ticks / elapsed))
    p95 = percentile.(0.95)
    worst = Enum.max(rates)

    Mix.shell().info("""

    Result of the load test
      time                         #{Float.round(elapsed, 1)} s
      ticks of the server          #{count} (#{Float.round(count / elapsed, 2)} each second, the target is #{rate})
      tick time, median            #{Float.round(percentile.(0.5), 2)} ms
      tick time, 95th percentile   #{Float.round(p95, 2)} ms   (target: 50 ms or less) #{verdict(p95 <= 50)}
      tick time, 99th percentile   #{Float.round(percentile.(0.99), 2)} ms
      tick time, maximum           #{Float.round(List.last(times) / 1000, 2)} ms
      memory of the VM, maximum    #{megabytes.(Enum.max(memory))} MB
      memory of the VM, at the end #{megabytes.(hd(memory))} MB
      memory of the world process  #{megabytes.(stats.process_memory)} MB
      bytes each second for each client
        minimum                    #{round(Enum.min(rates))}
        mean                       #{round(Enum.sum(rates) / length(rates))}
        maximum                    #{round(worst)}   (target: 30,000 or less) #{verdict(worst <= 30_000)}
      ticks each second that a client got, minimum  #{Float.round(Enum.min(ticks), 2)}
      world at the end             #{stats.carriers} carriers, #{stats.spare} spare bodies, #{stats.locked} locked bodies, #{stats.players} players, #{stats.helpers} helpers, #{stats.scent_cells} cells with scent, #{stats.food_nest} food at the nest, #{stats.stage - 1} crossings, #{stats.records} records
    """)
  end

  # A world where the colony crossed `rivers` rivers and has `locked` locked bodies or more.
  # A player locks into a random open cell with no walk: the rules of the lock are the
  # rules of the game.
  defp long_world(game, rivers, locked) do
    :rand.seed(:exsss, 2027)
    {world, id} = World.join(World.new(Keyword.merge(game, helpers: 0)), "Load builder")

    world =
      Stream.iterate(world, &place(&1, id))
      |> Enum.find(&(&1.stage > rivers and map_size(&1.locked) >= locked))

    World.leave(world, id)
  end

  defp place(world, id) do
    cell = world.open |> Map.keys() |> Enum.random()
    stand = world.grid |> Grid.neighbors(cell) |> Enum.find(&World.walkable?(world, &1))
    {x, z} = Grid.center(world.grid, stand)
    player = %{world.players[id] | x: x, z: z, cell: stand, ready_tick: 0, carry: nil}
    world = World.put_player(world, id, player)
    pile = max(1, world.stage - 1)

    world =
      if World.spare(world) == 0, do: World.add_nest_food(world, pile, 5), else: world

    {:ok, world} = World.lock(world, id, cell)
    # The events of these locks go to no client.
    elem(World.take_events(world), 0)
  end

  defp verdict(true), do: "OK"
  defp verdict(false), do: "NOT MET"

  # ---------------------------------------------------------------------------
  # One client: a WebSocket connection that uses the channel as a browser does.

  defp client(parent, n, port, nest, seconds) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, nodelay: true])
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    :ok =
      :gen_tcp.send(socket, [
        "GET /socket/websocket?vsn=2.0.0 HTTP/1.1\r\n",
        "Host: 127.0.0.1:#{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n",
        "Sec-WebSocket-Key: #{key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
      ])

    rest = handshake(socket, "")
    name = "Load #{String.pad_leading(Integer.to_string(n), 2, "0")}"
    send_frame(socket, 1, JSON.encode!(["1", "1", "world", "phx_join", %{name: name}]))
    :inet.setopts(socket, active: true)

    {x, z} = nest
    :timer.send_interval(100, :move)
    :timer.send_interval(30_000, :heartbeat)
    :rand.seed(:exsss, n)

    state = %{
      parent: parent,
      socket: socket,
      nest: nest,
      x: x,
      z: z,
      heading: :rand.uniform() * 6.28,
      buffer: rest,
      bytes: byte_size(rest),
      ticks: 0,
      until: System.monotonic_time(:millisecond) + (seconds + 30) * 1000
    }

    client_loop(count_frames(state))
  end

  defp handshake(socket, data) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
    data = data <> more

    case :binary.split(data, "\r\n\r\n") do
      [head, rest] ->
        "HTTP/1.1 101" <> _ = head
        rest

      [_] ->
        handshake(socket, data)
    end
  end

  defp client_loop(state) do
    receive do
      {:tcp, _socket, data} ->
        %{state | buffer: state.buffer <> data, bytes: state.bytes + byte_size(data)}
        |> count_frames()
        |> client_loop()

      :move ->
        state |> walk() |> client_loop()

      :heartbeat ->
        send_frame(state.socket, 1, JSON.encode!([nil, "hb", "phoenix", "heartbeat", %{}]))
        client_loop(state)

      :reset ->
        client_loop(%{state | bytes: 0, ticks: 0})

      :report ->
        send(state.parent, {:report, %{bytes: state.bytes, ticks: state.ticks}})
        :gen_tcp.close(state.socket)

      {:tcp_closed, _socket} ->
        Mix.raise("The server closed the connection of a client.")
    end
  end

  # A walk at random at the speed of a body, not more than 5 cells from the nest.
  defp walk(state) do
    {nx, nz} = state.nest
    heading = state.heading + (:rand.uniform() - 0.5) * 0.8
    x = state.x + :math.sin(heading) * 0.38
    z = state.z + :math.cos(heading) * 0.38

    if :math.sqrt((x - nx) ** 2 + (z - nz) ** 2) > 5 do
      # Turn in the direction of the nest.
      %{state | heading: :math.atan2(nx - state.x, nz - state.z)}
    else
      move = Protocol.encode_move(x, z, heading)
      # A binary push of the channel protocol: kind 0, the sizes, then the texts and the data.
      send_frame(state.socket, 2, <<0, 1, 0, 5, 1, "1", "world", "m", move::binary>>)
      %{state | x: x, z: z, heading: heading}
    end
  end

  # Counts the tick messages in the data. A tick is a broadcast (kind 2) with the event "t".
  defp count_frames(%{buffer: buffer} = state) do
    case frame(buffer) do
      {:ok, payload, rest} ->
        ticks =
          case payload do
            <<2, 5, 1, "world", "t", _::binary>> -> state.ticks + 1
            _ -> state.ticks
          end

        count_frames(%{state | buffer: rest, ticks: ticks})

      :more ->
        state
    end
  end

  defp frame(<<_fin_opcode::8, 0::1, 127::7, size::64, payload::binary-size(size), rest::binary>>),
    do: {:ok, payload, rest}

  defp frame(<<_fin_opcode::8, 0::1, 126::7, size::16, payload::binary-size(size), rest::binary>>),
    do: {:ok, payload, rest}

  defp frame(<<_fin_opcode::8, 0::1, size::7, payload::binary-size(size), rest::binary>>)
       when size < 126,
       do: {:ok, payload, rest}

  defp frame(_), do: :more

  # A frame from a client has a mask. The mask here is 0, thus the data does not change.
  defp send_frame(socket, opcode, payload) do
    size = byte_size(payload)

    header =
      cond do
        size < 126 -> <<1::1, 0::3, opcode::4, 1::1, size::7>>
        size < 65_536 -> <<1::1, 0::3, opcode::4, 1::1, 126::7, size::16>>
        true -> <<1::1, 0::3, opcode::4, 1::1, 127::7, size::64>>
      end

    :ok = :gen_tcp.send(socket, [header, <<0::32>>, payload])
  end
end
