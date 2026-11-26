defmodule Mix.Tasks.Colony.Reset do
  @shortdoc "Deletes the save file of the world"

  @moduledoc """
  Deletes the save file of the world. The next start of the server makes a new world.

      mix colony.reset

  Stop the server first. A server that runs writes the file again.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    path = Colony.Store.path(Application.fetch_env!(:colony, :game))

    case Colony.Store.reset(path) do
      :deleted -> Mix.shell().info("Deleted #{path}.")
      :none -> Mix.shell().info("There is no save file at #{path}.")
    end
  end
end
