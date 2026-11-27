defmodule Mix.Tasks.Colony.Records do
  @shortdoc "Prints the records of the bridges and the story from the save file, as JSON"

  @moduledoc """
  Prints the records of the bridges and the story of the world from the save file, as JSON.

      mix colony.records

  The result has two parts. `records` has the records of the bridges, the newest first.
  `story` has all the locks in the order of their times, and the players with their bodies
  and their food.

  `COLONY_SAVE_FILE` sets the path of the save file.
  """

  use Mix.Task

  alias Colony.{Protocol, Store, World}

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    cfg = Application.fetch_env!(:colony, :game)
    version = World.save_version()

    result =
      case Store.load(Store.path(cfg)) do
        {:ok, %{version: ^version} = saved} ->
          # The story needs the rivers. The world of the file gives them. No worker and no
          # helper is necessary.
          world =
            World.new(Keyword.merge(cfg, helpers: 0), %{saved | workers: %{carrier: 0, spare: 0}})

          story = World.story(world)

          %{
            records: Enum.map(world.records, &Protocol.record/1),
            story: %{story | time: List.last([story.start | Enum.map(story.locks, & &1.time)])}
          }

        _ ->
          %{records: [], story: nil}
      end

    IO.puts(JSON.encode!(result))
  end
end
