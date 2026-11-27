defmodule ColonyWeb.WorldChannel do
  @moduledoc """
  The channel between one browser and the world.

  Events to the client: "s" (all the state, binary), "t" (the changes of a tick, binary),
  "you" (a message for this player only), "records" (all the records of the bridges) and
  "record" (one record that is new or that changed).
  Events from the client: "m" (move, binary), "lock", "body", "name", "me", "story" and
  "ping".

  The join has the name, and the secret number of the page as text: the server knows the
  person by it.

  A message with wrong data gets the reply "error" or no reply. It does not stop the channel.
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
    # A client that only looks gets no body: the demo mode and the story.
    look? = params["look"] == true
    # If the world process stops, this channel stops also. The page then joins again and
    # gets the new world.
    Process.monitor(Server)

    {:ok, id, snapshot} =
      Server.join(self(), clean_name(params["name"]), look?, clean_secret(params["secret"]))

    push(socket, "s", {:binary, snapshot})
    push(socket, "records", %{records: Server.records()})
    {:noreply, assign(socket, :id, if(look?, do: nil, else: id))}
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
    # `at` is the position of the body, as text. A value that is not correct text is not used.
    position =
      with at when is_binary(at) <- params["at"],
           {:ok, binary} <- Base.decode64(at) do
        binary
      else
        _ -> nil
      end

    case Server.lock(id, cell, position) do
      {:ok, body} -> {:reply, {:ok, body}, socket}
      :error -> {:reply, :error, socket}
    end
  end

  def handle_in("lock", _params, socket), do: {:reply, :error, socket}

  # The name, the time and the count of a locked body, for a player who taps it.
  def handle_in("body", %{"cell" => cell}, socket) when is_integer(cell) do
    case Server.body(cell) do
      nil -> {:reply, :error, socket}
      body -> {:reply, {:ok, body}, socket}
    end
  end

  def handle_in("body", _params, socket), do: {:reply, :error, socket}

  # The player has a new name. The page makes the name: a player types no name.
  def handle_in("name", %{"name" => name}, %{assigns: %{id: id}} = socket)
      when id != nil and is_binary(name) do
    Server.rename(id, clean_name(name))
    {:reply, :ok, socket}
  end

  def handle_in("name", _params, socket), do: {:reply, :error, socket}

  # The numbers of the person of this player, for the panel of the name.
  def handle_in("me", _params, %{assigns: %{id: id}} = socket) when id != nil do
    case Server.numbers(id) do
      nil -> {:reply, :error, socket}
      numbers -> {:reply, {:ok, numbers}, socket}
    end
  end

  def handle_in("me", _params, socket), do: {:reply, :error, socket}

  # The players with their bodies and their food, for the story.
  def handle_in("story", _params, socket) do
    story = Server.story()
    {:reply, {:ok, Map.take(story, [:start, :time, :complete, :crossings, :food, :names])}, socket}
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

  # A secret number is text of 16 to 64 letters and digits. Other values are not used.
  defp clean_secret(secret) when is_binary(secret) do
    if secret =~ ~r/^[A-Za-z0-9]{16,64}$/, do: secret
  end

  defp clean_secret(_), do: nil
end
