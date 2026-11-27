defmodule Colony.Table do
  @moduledoc """
  The table of the open cells: the bodies of a bridge across a river of each width.

  A bridge grows by locks into open cells (`Colony.Support.open/5`) until it touches the
  far land, or until no cell is open. "Best" always takes the open cell that gives the
  highest support of the top row. "Random" takes a random open cell: a player who taps
  each time the button is bright. The config has the result: `bridge_best` and
  `bridge_random` (the highest of 200 random runs, with the seeds 1 to 200).

  `mix colony.table` makes the table again. `test/open_test.exs` checks it.
  """

  alias Colony.{Grid, Support}

  @doc """
  Builds one bridge across a river of `width` rows with the support rule of `cfg`. `how`
  is `:best` or `{:random, seed}`. Returns `{bodies, crossed?}`.
  """
  def run(cfg, width, how) do
    cfg = Keyword.merge(cfg, rivers: [{width, width}], endless: false, seed: 1)
    grid = Grid.new(cfg, 1)
    rule = Support.rule(cfg)
    row = Grid.river_start(grid, 1)
    start = for col <- 24..36, do: Grid.cell(grid, row, col)
    if match?({:random, _}, how), do: :rand.seed(:exsss, elem(how, 1))

    locked =
      Enum.reduce_while(1..1000, %{}, fn _, locked ->
        case Support.open(grid, rule, locked, 1, start) do
          [] -> {:halt, locked}
          open -> {:cont, Map.put(locked, pick(grid, rule, locked, Enum.sort(open), how), true)}
        end
      end)

    {map_size(locked), Enum.any?(Map.keys(locked), &Grid.touches_land?(grid, &1, 1))}
  end

  defp pick(grid, rule, locked, open, :best) do
    Enum.max_by(open, fn cell ->
      next = Map.put(locked, cell, true)
      top = next |> Map.keys() |> Enum.map(&Grid.row(grid, &1)) |> Enum.max()
      Support.top_support(grid, Support.calculate(grid, rule, next), top)
    end)
  end

  defp pick(_grid, _rule, _locked, open, {:random, _seed}), do: Enum.random(open)

  @doc """
  The table for some widths: `[%{width, best, low, high, stuck}]`. `low` and `high` are
  the least and the most bodies of `runs` random runs. `stuck` is the number of runs that
  stopped before the far land.
  """
  def table(cfg, widths, runs) do
    jobs =
      for width <- widths,
          how <- [:best | for(seed <- 1..runs//1, do: {:random, seed})],
          do: {width, how}

    results =
      jobs
      |> Task.async_stream(fn {width, how} -> {width, how, run(cfg, width, how)} end,
        timeout: :infinity,
        ordered: false,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.map(fn {:ok, result} -> result end)

    for width <- widths do
      rows = for {^width, how, result} <- results, do: {how, result}
      {best, best_crossed} = rows |> Enum.find(&(elem(&1, 0) == :best)) |> elem(1)
      random = for {{:random, _}, result} <- rows, do: result
      counts = Enum.map(random, &elem(&1, 0))

      %{
        width: width,
        best: best,
        low: Enum.min(counts, fn -> nil end),
        high: Enum.max(counts, fn -> nil end),
        stuck: Enum.count(random, &(not elem(&1, 1))) + if(best_crossed, do: 0, else: 1)
      }
    end
  end
end
