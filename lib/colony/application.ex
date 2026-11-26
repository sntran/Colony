defmodule Colony.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    world = if Application.get_env(:colony, :start_world, true), do: [Colony.Server], else: []

    children =
      [{Phoenix.PubSub, name: Colony.PubSub}] ++ world ++ [ColonyWeb.Endpoint]

    Supervisor.start_link(children, strategy: :one_for_one, name: Colony.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ColonyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
