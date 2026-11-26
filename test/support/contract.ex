defmodule Colony.Contract do
  @moduledoc """
  The TLA+ contract between a player and the world: `specs/Colony.tla`.

  `Accord.Spec.Monitor` uses this module to monitor a real world. Each message to the
  world is an action of the contract with the same name: the call `{:move, :p1, 3}` with
  the reply `:ok` is the step `Move("p1", 3, "ok")`.
  """

  use Accord.Spec, file: "../../specs/Colony.tla", config: "../../specs/ColonyPlay.cfg"

  alias Accord.TLA.Checker.Machine

  # These messages control the test. They are not part of the contract.
  @impl true
  def handle_call({:tick, _count}, _reply), do: :ignore
  def handle_call({:scent, _player, _on}, _reply), do: :ignore
  def handle_call({:demo, _on}, _reply), do: :ignore
  def handle_call(request, reply), do: super(request, reply)

  @doc """
  The game config of a world that has the numbers of a config of the contract.

  The contract has supports and costs in half units. `changes` are other values of the
  game config.
  """
  def game_config(config_path, changes \\ []) do
    {:ok, machine} = Machine.load(spec_path(), config: Path.expand(config_path))
    constant = &Map.fetch!(machine.ctx.constants, &1)
    width = constant.("Width")
    nest = constant.("Nest")

    :colony
    |> Application.fetch_env!(:game)
    |> Keyword.merge(
      width: width,
      near_rows: constant.("NearRows"),
      gap_rows: constant.("GapRows"),
      far_rows: constant.("FarRows"),
      bank_support: constant.("Bank") / 2,
      cost_alone: constant.("Alone") / 2,
      cost_beside: constant.("Beside") / 2,
      nest: {div(nest, width), rem(nest, width)},
      food_rows_from_gap: 1,
      food_column: 0,
      seed: 1
    )
    |> Keyword.merge(changes)
  end

  @doc "The text of a config of the contract that has the numbers of a game config."
  def config_text(game, players) do
    {nest_row, nest_col} = Keyword.fetch!(game, :nest)
    names = Enum.map_join(players, ", ", &~s("#{&1}"))

    """
    CONSTANTS
        Width = #{game[:width]}
        NearRows = #{game[:near_rows]}
        GapRows = #{game[:gap_rows]}
        FarRows = #{game[:far_rows]}
        Bank = #{half_units(game[:bank_support])}
        Alone = #{half_units(game[:cost_alone])}
        Beside = #{half_units(game[:cost_beside])}
        MaxLetGo = 1
        Players = {#{names}}
        Nest = #{nest_row * game[:width] + nest_col}
    SPECIFICATION Spec
    """
  end

  @doc "The path of the contract."
  def spec_path, do: Path.expand("../../specs/Colony.tla", __DIR__)

  defp half_units(value) do
    doubled = value * 2
    true = doubled == trunc(doubled)
    trunc(doubled)
  end
end

defmodule Colony.Contract.Server do
  @moduledoc """
  A real world behind the messages of the contract.

  The monitor sends each call to this process. The process changes the world with the
  same functions that the game server uses, then it moves the world some ticks. It sends
  what the world does in these ticks to the monitor as events: a worker locks, workers let
  go, a player gets a new body.
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

  @doc "The number of events of each kind that the process sent to the monitor."
  def events(server), do: GenServer.call(server, :events)

  @impl true
  def init(game) do
    {:ok, %{world: World.new(game), ids: %{}, scent: MapSet.new(), monitor: nil, events: %{}}}
  end

  @impl true
  def handle_call({:attach, monitor}, _from, state), do: {:reply, :ok, %{state | monitor: monitor}}
  def handle_call(:world, _from, state), do: {:reply, state.world, state}
  def handle_call(:world_ids, _from, state), do: {:reply, state.ids, state}
  def handle_call(:events, _from, state), do: {:reply, state.events, state}

  # Questions. They do not move the world.
  def handle_call(:look, _from, state) do
    cells = fn kind ->
      for {cell, %{kind: ^kind}} <- state.world.locked, into: MapSet.new(), do: cell
    end

    {:reply, {cells.(:worker), cells.(:player)}, state}
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
      {nil, _ids} -> {:error, state, @pace}
      {id, ids} -> {:ok, %{state | world: World.leave(state.world, id), ids: ids}, @pace}
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

  defp act({:lock, name, cell}, state) do
    case state.ids[name] && World.lock(state.world, state.ids[name], cell) do
      {:ok, world} -> {:ok, %{state | world: world}, @pace}
      _ -> {:error, state, @pace}
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

  defp act({:demo, on?}, state),
    do: {:ok, %{state | world: World.set_demo(state.world, on?)}, @pace}

  defp act({:tick, count}, state), do: {:ok, state, count}

  defp player(state, name), do: state.ids[name] && state.world.players[state.ids[name]]

  defp run(state, ticks) do
    Enum.reduce(1..ticks//1, state, fn _, state ->
      {world, events} = World.tick(state.world)
      names = Map.new(state.ids, fn {name, id} -> {id, name} end)

      # The order is the order of the tick: let go, new bodies, then the workers move.
      let_go = if events.let_go == [], do: [], else: [{:workers_let_go, MapSet.new(events.let_go)}]

      respawns =
        for {id, %{state: "alive"}} <- Enum.reverse(events.you), name = names[id] do
          {:respawn, name}
        end

      locks = for {cell, %{kind: :worker}} <- Enum.reverse(events.locks), do: {:worker_locked, cell}

      Enum.reduce(let_go ++ respawns ++ locks, %{state | world: world}, fn message, state ->
        if state.monitor, do: Monitor.event(state.monitor, message)
        %{state | events: Map.update(state.events, elem(message, 0), 1, &(&1 + 1))}
      end)
    end)
  end
end
