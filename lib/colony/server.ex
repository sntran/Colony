defmodule Colony.Server do
  @moduledoc """
  The process that holds the world.

  It moves the world one tick at a time, sends the changes to the clients, and saves the
  world to the file.
  """

  use GenServer

  require Logger

  alias Colony.{Protocol, Store, World}

  @topic "world"
  # The number of tick times that the process keeps for the statistics.
  @keep_times 20_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "A client joins. Returns `{:ok, id, snapshot}`. A demo client gets no body."
  def join(pid, name, demo?), do: GenServer.call(__MODULE__, {:join, pid, name, demo?})

  @doc "A player tells where the body is."
  def move(id, binary), do: GenServer.cast(__MODULE__, {:move, id, binary})

  @doc "A player locks the body into a cell. Returns `:ok` or `:error`."
  def lock(id, cell, position), do: GenServer.call(__MODULE__, {:lock, id, cell, position})

  @doc "The tick times in microseconds, sorted, and the size of the world. `reset: true` then removes the times."
  def stats(opts \\ []), do: GenServer.call(__MODULE__, {:stats, opts})

  @doc "Saves the world now."
  def save, do: GenServer.call(__MODULE__, :save)

  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    cfg = Application.fetch_env!(:colony, :game)
    path = Store.path(cfg)

    world =
      case Store.load(path) do
        {:ok, saved} ->
          world = World.new(cfg, saved)
          Logger.info("World loaded from #{path}: #{map_size(world.locked)} locked bodies.")
          world

        :none ->
          Logger.info("New world. The save file is #{path}.")
          World.new(cfg)
      end

    rate = world.p.rate

    state = %{
      world: world,
      path: path,
      interval: div(1000, rate),
      save_ticks: Keyword.fetch!(cfg, :save_seconds) * rate,
      next_at: System.monotonic_time(:millisecond),
      # pid => {monitor reference, player id or :demo}
      clients: %{},
      # player id => pid
      pids: %{},
      times: [],
      time_count: 0
    }

    {:ok, schedule(state)}
  end

  @impl true
  def handle_call({:join, pid, name, demo?}, _from, state) do
    reference = Process.monitor(pid)

    if demo? do
      state = put_in(state.clients[pid], {reference, :demo})
      state = update_demo(state)
      {:reply, {:ok, 0xFFFF, Protocol.snapshot(state.world, 0xFFFF)}, state}
    else
      {world, id} = World.join(state.world, name)

      state = %{
        state
        | world: world,
          clients: Map.put(state.clients, pid, {reference, id}),
          pids: Map.put(state.pids, id, pid)
      }

      {:reply, {:ok, id, Protocol.snapshot(world, id)}, state}
    end
  end

  def handle_call({:lock, id, cell, position}, _from, state) do
    world = apply_move(state.world, id, position)
    {result, world} = World.lock(world, id, cell)
    {:reply, if(result == :ok, do: :ok, else: :error), %{state | world: world}}
  end

  def handle_call({:stats, opts}, _from, state) do
    stats = %{
      tick_times: Enum.sort(state.times),
      tick: state.world.tick,
      workers: state.world.worker_count,
      free_workers: map_size(state.world.workers),
      locked: map_size(state.world.locked),
      players: map_size(state.world.players),
      food_pile: state.world.food_pile,
      food_nest: state.world.food_nest,
      scent_cells: map_size(state.world.scent),
      process_memory: Process.info(self(), :memory) |> elem(1)
    }

    state = if opts[:reset], do: %{state | times: [], time_count: 0}, else: state
    {:reply, stats, state}
  end

  def handle_call(:save, _from, state) do
    {:reply, Store.save(state.path, World.to_save(state.world)), state}
  end

  @impl true
  def handle_cast({:move, id, binary}, state) do
    {:noreply, %{state | world: apply_move(state.world, id, binary)}}
  end

  @impl true
  def handle_info(:tick, state) do
    start = System.monotonic_time(:microsecond)
    {world, events} = World.tick(state.world, System.os_time(:second))

    for {id, message} <- Enum.reverse(events.you), pid = state.pids[id] do
      send(pid, {:you, message})
    end

    if state.clients != %{} do
      ColonyWeb.Endpoint.broadcast(@topic, "t", {:binary, Protocol.tick(world, events)})
    end

    if rem(world.tick, state.save_ticks) == 0, do: save_later(state.path, world)

    time = System.monotonic_time(:microsecond) - start
    state = keep_time(%{state | world: world}, time)
    {:noreply, schedule(state)}
  end

  def handle_info({:DOWN, _reference, :process, pid, _reason}, state) do
    case Map.pop(state.clients, pid) do
      {nil, _} ->
        {:noreply, state}

      {{_reference, :demo}, clients} ->
        {:noreply, update_demo(%{state | clients: clients})}

      {{_reference, id}, clients} ->
        state = %{
          state
          | clients: clients,
            pids: Map.delete(state.pids, id),
            world: World.leave(state.world, id)
        }

        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Store.save(state.path, World.to_save(state.world))
    Logger.info("World saved to #{state.path}.")
  end

  # ---------------------------------------------------------------------------

  defp apply_move(world, id, binary) when is_binary(binary) do
    case Protocol.decode_move(binary) do
      {:ok, x, z, heading, scent?} -> World.move(world, id, x, z, heading, scent?)
      :error -> world
    end
  end

  defp apply_move(world, _id, _other), do: world

  defp update_demo(state) do
    demo? = Enum.any?(state.clients, fn {_pid, {_reference, id}} -> id == :demo end)
    %{state | world: World.set_demo(state.world, demo?)}
  end

  # The ticks keep to the clock: a slow tick does not make all the later ticks late.
  defp schedule(state) do
    now = System.monotonic_time(:millisecond)
    next_at = state.next_at + state.interval
    # If the server is far behind, do not try to get the lost ticks back.
    next_at = if next_at < now - 5 * state.interval, do: now, else: next_at
    Process.send_after(self(), :tick, max(0, next_at - now))
    %{state | next_at: next_at}
  end

  defp keep_time(state, time) do
    if state.time_count >= @keep_times do
      %{state | times: [time | Enum.take(state.times, div(@keep_times, 2))], time_count: div(@keep_times, 2) + 1}
    else
      %{state | times: [time | state.times], time_count: state.time_count + 1}
    end
  end

  # The write is in a different process. Thus a slow disk does not make a tick late.
  defp save_later(path, world) do
    saved = World.to_save(world)

    spawn(fn ->
      try do
        Store.save(path, saved)
      rescue
        error -> Logger.warning("Cannot save the world: #{inspect(error)}")
      end
    end)
  end
end
