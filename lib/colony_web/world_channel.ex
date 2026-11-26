defmodule ColonyWeb.WorldChannel do
  @moduledoc """
  The channel between one browser and the world.

  Events to the client: "s" (all the state, binary), "t" (the changes of a tick, binary)
  and "you" (a message for this player only).
  Events from the client: "m" (move, binary), "lock" and "ping".
  """

  use Phoenix.Channel

  alias Colony.Server

  @max_name 16

  @impl true
  def join("world", params, socket) do
    # The snapshot goes out after the join. At that time the channel gets the ticks, thus
    # the client loses no tick between the snapshot and the first tick.
    send(self(), {:after_join, params})
    {:ok, assign(socket, :id, nil)}
  end

  @impl true
  def handle_info({:after_join, params}, socket) do
    demo? = params["demo"] == true
    # If the world process stops, this channel stops also. The page then joins again and
    # gets the new world.
    Process.monitor(Server)
    {:ok, id, snapshot} = Server.join(self(), clean_name(params["name"]), demo?)
    push(socket, "s", {:binary, snapshot})
    {:noreply, assign(socket, :id, if(demo?, do: nil, else: id))}
  end

  def handle_info({:you, message}, socket) do
    push(socket, "you", message)
    {:noreply, socket}
  end

  def handle_info({:DOWN, _reference, :process, _pid, _reason}, socket) do
    {:stop, :shutdown, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_in("m", {:binary, binary}, %{assigns: %{id: id}} = socket) when id != nil do
    Server.move(id, binary)
    {:noreply, socket}
  end

  def handle_in("lock", %{"cell" => cell} = params, %{assigns: %{id: id}} = socket)
      when id != nil and is_integer(cell) do
    position =
      case Base.decode64(params["at"] || "") do
        {:ok, binary} -> binary
        :error -> nil
      end

    case Server.lock(id, cell, position) do
      :ok -> {:reply, :ok, socket}
      :error -> {:reply, :error, socket}
    end
  end

  def handle_in("ping", _params, socket), do: {:reply, :ok, socket}

  def handle_in(_event, _params, socket), do: {:noreply, socket}

  # A name is plain text of 1 to 16 characters.
  defp clean_name(name) when is_binary(name) do
    name =
      name
      |> String.replace(~r/[^\p{L}\p{N} _-]/u, "")
      |> String.trim()
      |> String.slice(0, @max_name)

    if name == "", do: "Guest", else: name
  end

  defp clean_name(_), do: "Guest"
end
