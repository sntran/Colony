defmodule Mix.Tasks.Colony.Table do
  @shortdoc "Makes the table of the open cells and compares it with the config"

  @moduledoc """
  Makes the table of the open cells for each width from 5 to 27 rows, with "Best" and 200
  random runs, and compares it with `bridge_best` and `bridge_random` of the config.

      mix colony.table [--runs 200]

  See `Colony.Table`. With 4 cores, 200 runs take about 2 minutes.
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [runs: :integer])
    runs = opts[:runs] || 200
    Mix.Task.run("app.config")
    cfg = Application.fetch_env!(:colony, :game)
    rows = Colony.Table.table(cfg, Enum.to_list(5..27), runs)
    best = Keyword.fetch!(cfg, :bridge_best)
    random = Keyword.fetch!(cfg, :bridge_random)

    Mix.shell().info("width  best  config   random low  high  config  stopped")

    for row <- rows do
      Mix.shell().info(
        String.pad_leading("#{row.width}", 5) <>
          String.pad_leading("#{row.best}", 6) <>
          String.pad_leading("#{best[row.width]}", 8) <>
          String.pad_leading("#{row.low}", 13) <>
          String.pad_leading("#{row.high}", 6) <>
          String.pad_leading("#{random[row.width]}", 8) <> String.pad_leading("#{row.stuck}", 9)
      )
    end

    same? =
      Enum.all?(rows, &(&1.best == best[&1.width] and (runs != 200 or &1.high == random[&1.width])))

    stuck = Enum.sum(Enum.map(rows, & &1.stuck))

    Mix.shell().info(
      if(same?,
        do: "The table is the table of the config.",
        else: "The table is NOT the table of the config."
      ) <>
        " Runs that stopped before the far land: #{stuck}."
    )

    if not same? or stuck > 0, do: exit({:shutdown, 1})
  end
end
