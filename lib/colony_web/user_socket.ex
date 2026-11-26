defmodule ColonyWeb.UserSocket do
  use Phoenix.Socket

  channel("world", ColonyWeb.WorldChannel)

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
