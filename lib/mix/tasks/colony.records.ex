defmodule Mix.Tasks.Colony.Records do
  @shortdoc "Prints the records of the bridges from the save file, as JSON"

  @moduledoc """
  Prints the records of the bridges from the save file, as JSON. The newest record is first.

      mix colony.records

  `COLONY_SAVE_FILE` sets the path of the save file.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    path = Colony.Store.path(Application.fetch_env!(:colony, :game))

    records =
      case Colony.Store.load(path) do
        {:ok, %{version: 2, records: records}} -> Enum.map(records, &Colony.Protocol.record/1)
        _ -> []
      end

    IO.puts(JSON.encode!(records))
  end
end
