defmodule Colony.Contract do
  @moduledoc """
  The TLA+ contract between a player and the world: `specs/Colony.tla`.

  `Accord.Spec.Monitor` uses this module to monitor a real world. Each message to the
  world is an action of the contract with the same name: the call `{:move, :p1, 3}` with
  the reply `:ok` is the step `Move("p1", 3, "ok")`.
  """

  use Accord.Spec, file: "../../specs/Colony.tla", config: "../../specs/ColonyPlay.cfg"

  # These messages control the test. They are not part of the contract.
  @impl true
  def handle_call({:tick, _count}, _reply), do: :ignore
  def handle_call({:scent, _player, _on}, _reply), do: :ignore
  def handle_call(request, reply), do: super(request, reply)

  @doc """
  The game config of a world that has the numbers of a config of the contract.

  The river of the config must have the same width in all its columns. `changes` are other
  values of the game config.
  """
  def game_config(config_path, changes \\ []) do
    config = File.read!(config_path)

    number = fn name ->
      Regex.run(~r/^\s*#{name} = (\d+)/m, config) |> Enum.at(1) |> String.to_integer()
    end

    width = number.("Width")
    nest = number.("Nest")
    [rows] = Enum.uniq(sequence(config, "River"))
    costs = sequence(config, "Costs")
    scale = hd(costs)

    :colony
    |> Application.fetch_env!(:game)
    |> Keyword.merge(
      width: width,
      near_rows: number.("NearRows"),
      far_rows: number.("FarRows"),
      river_min: rows,
      river_max: rows,
      bank_support: div(number.("Bank"), scale),
      row_max: length(costs),
      nest: {div(nest, width), rem(nest, width)},
      seed: 1
    )
    |> Keyword.merge(changes)
  end

  # A config gives a sequence as the name of a definition of a module: `River <- Name`.
  # The definition is one line: `Name == <<1, 2, 3>>`.
  defp sequence(config, constant) do
    [_, name] = Regex.run(~r/^\s*#{constant} <- (\w+)/m, config)

    modules =
      Path.wildcard(Path.join(Path.dirname(spec_path()), "*.tla")) |> Enum.map(&File.read!/1)

    [_, numbers] =
      Enum.find_value(modules, &Regex.run(~r/^#{name} == <<([\d, ]+)>>/m, &1)) ||
        raise "no definition #{name} == <<...>> in the modules"

    numbers |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))
  end

  @doc """
  The text of a module and of a config of the contract that have the numbers of a world:
  its grid, its river and its support rule. Returns `{module_text, config_text}` for a
  module with the name `name`.
  """
  def plan_files(world, name, lines \\ "") do
    grid = world.grid
    river = grid.river |> Tuple.to_list() |> Enum.join(", ")
    costs = world.rule.costs |> Tuple.to_list() |> Enum.join(", ")

    module = """
    ---- MODULE #{name} ----
    EXTENDS Colony
    TheRiver == <<#{river}>>
    TheCosts == <<#{costs}>>
    ====
    """

    config = """
    CONSTANTS
        Width = #{grid.width}
        NearRows = #{grid.near_rows}
        FarRows = #{Keyword.fetch!(world.cfg, :far_rows)}
        Bank = #{world.rule.bank}
        River <- TheRiver
        Costs <- TheCosts
        Players = {}
        Nest = #{grid.nest}
    SPECIFICATION Spec
    #{lines}
    """

    {module, config}
  end

  @doc "The path of the contract."
  def spec_path, do: Path.expand("../../specs/Colony.tla", __DIR__)
end

defmodule Colony.Contract.Server do
  @moduledoc """
  A real world behind the messages of the contract.

  The monitor sends each call to this process. The process changes the world with the
  same functions that the game server uses, then it moves the world some ticks. It sends
  what the world does in these ticks to the monitor as events: a helper locks, a body can
  lock again, a player gets a new body.
  """

  use GenServer

  alias Accord.Spec.Monitor
  alias Colony.{Grid, World}

  # The ticks after each message. In this time a body gets the movement for one cell.
  @pace 3

  def start_link(game), do: GenServer.start_link(__MODULE__, game)

  @doc "Tells the process where the events go."
  def attach(server, monitor), do: GenServer.call(server, {:attach, monitor})

  @doc "The world, for a look from a test."
  def world(server), do: GenServer.call(server, :world)

  @doc "The players that are in the world: name => id."
  def ids(server), do: GenServer.call(server, :ids)

  @doc "The number of events of each kind that the process sent to the monitor."
  def events(server), do: GenServer.call(server, :events)

  @impl true
  def init(game) do
    state = %{
      world: World.new(game),
      ids: %{},
      scent: MapSet.new(),
      # The players with a body that cannot lock now.
      resting: MapSet.new(),
      monitor: nil,
      events: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:attach, monitor}, _from, state), do: {:reply, :ok, %{state | monitor: monitor}}
  def handle_call(:world, _from, state), do: {:reply, state.world, state}
  def handle_call(:ids, _from, state), do: {:reply, state.ids, state}
  def handle_call(:events, _from, state), do: {:reply, state.events, state}

  # Questions. They do not move the world.
  def handle_call(:look, _from, state) do
    {:reply, MapSet.new(Map.keys(state.world.locked)), state}
  end

  def handle_call({:where, name}, _from, state) do
    nest = state.world.grid.nest

    reply =
      case player(state, name) do
        nil -> {:out, nest}
        %{state: :alive, cell: cell} -> {:alive, cell}
        _dead -> {:dead, nest}
      end

    {:reply, reply, state}
  end

  # All the other messages change the world, then the world moves some ticks.
  def handle_call(message, _from, state) do
    {reply, state, ticks} = act(message, state)
    {:reply, reply, run(state, ticks)}
  end

  defp act({:join, name}, state) do
    if is_map_key(state.ids, name) do
      {:error, state, @pace}
    else
      {world, id} = World.join(state.world, Atom.to_string(name))
      {:ok, %{state | world: world, ids: Map.put(state.ids, name, id)}, @pace}
    end
  end

  defp act({:leave, name}, state) do
    case Map.pop(state.ids, name) do
      {nil, _ids} ->
        {:error, state, @pace}

      {id, ids} ->
        resting = MapSet.delete(state.resting, name)
        {:ok, %{state | world: World.leave(state.world, id), ids: ids, resting: resting}, @pace}
    end
  end

  # The body goes to the center of the cell. The world accepts the move or not.
  defp act({:move, name, cell}, state) do
    world = state.world

    with id when id != nil <- state.ids[name],
         %{state: :alive} <- world.players[id],
         true <- cell in 0..(world.grid.count - 1) do
      {x, z} = Grid.center(world.grid, cell)
      world = World.move(world, id, x, z, 0.0, MapSet.member?(state.scent, name))
      moved? = world.players[id].x == x and world.players[id].z == z
      {if(moved?, do: :ok, else: :no), %{state | world: world}, @pace}
    else
      _ -> {:no, state, @pace}
    end
  end

  # The reply has the cell of the new body of the player, or -1.
  defp act({:lock, name, cell}, state) do
    case state.ids[name] && World.lock(state.world, state.ids[name], cell) do
      {:ok, world} ->
        case world.players[state.ids[name]] do
          %{state: :alive, cell: at} ->
            {{:ok, at}, %{state | world: world, resting: MapSet.put(state.resting, name)}, @pace}

          _dead ->
            {{:ok, -1}, %{state | world: world}, @pace}
        end

      _ ->
        {{:error, -1}, state, @pace}
    end
  end

  # While the scent is on, the body puts scent on its cell.
  defp act({:scent, name, on?}, state) do
    scent = if on?, do: MapSet.put(state.scent, name), else: MapSet.delete(state.scent, name)
    world = state.world

    world =
      case player(state, name) do
        %{state: :alive} = body -> World.move(world, state.ids[name], body.x, body.z, 0.0, on?)
        _ -> world
      end

    {:ok, %{state | world: world, scent: scent}, @pace}
  end

  defp act({:tick, count}, state), do: {:ok, state, count}

  defp player(state, name), do: state.ids[name] && state.world.players[state.ids[name]]

  defp run(state, ticks) do
    Enum.reduce(1..ticks//1, state, fn _, state ->
      {world, events} = World.tick(state.world)
      names = Map.new(state.ids, fn {name, id} -> {id, name} end)
      state = %{state | world: world}

      # The order is the order of the tick: new bodies, then the helpers.
      respawns =
        for {id, %{state: "alive"}} <- Enum.reverse(events.you), name = names[id] do
          {:respawn, name}
        end

      # A body that a player took can lock again after some ticks.
      rested =
        for name <- state.resting,
            body = player(state, name),
            body.state == :alive and world.tick >= body.ready_tick do
          {:rested, name}
        end

      locks =
        for {cell, %{helper: true}, _id} <- Enum.reverse(events.locks), do: {:helper_locked, cell}

      resting =
        Enum.reduce(rested, state.resting, fn {:rested, name}, set -> MapSet.delete(set, name) end)

      Enum.reduce(respawns ++ rested ++ locks, %{state | resting: resting}, fn message, state ->
        if state.monitor, do: Monitor.event(state.monitor, message)
        %{state | events: Map.update(state.events, elem(message, 0), 1, &(&1 + 1))}
      end)
    end)
  end
end
