defmodule Mix.Tasks.Colony.Contracts do
  @shortdoc "Checks the TLA+ contracts of the game"

  @moduledoc """
  Checks the TLA+ contracts in `specs/` with the native TLA+ checker of accord.

      mix colony.contracts [MODULE ...]

  With no module names, the task checks all the modules: `Bridge`, `BridgeWide`,
  `BridgeOpen`, `BridgeOneWide`, `BridgeTwoWide`, `BridgeThreeWide`, `BridgeNineRows` and
  `Colony`. Each module has a
  config file with the same name: the model that the checker explores.

  The checker is a package for development and tests. It is not in a production build.
  """

  use Mix.Task

  @modules ~w(Bridge BridgeWide BridgeOpen BridgeOneWide BridgeTwoWide BridgeThreeWide BridgeNineRows Colony)

  @impl true
  def run(args) do
    names = if args == [], do: @modules, else: args

    checker = Module.concat(["Accord", "TLA", "Checker"])

    if not Code.ensure_loaded?(checker) do
      Mix.raise("The checker is not there. Use the dev or the test environment.")
    end

    results = Enum.map(names, &check(checker, &1))
    if :error in results, do: Mix.raise("A contract has a fault.")
  end

  defp check(checker, name) do
    path = Path.expand("specs/#{name}.tla")
    if not File.exists?(path), do: Mix.raise("There is no contract #{path}.")

    {time, result} = :timer.tc(fn -> checker.check(path, workers: :auto) end)
    seconds = Float.round(time / 1_000_000, 1)

    case result do
      {:ok, stats} ->
        Mix.shell().info(
          "ok     #{name}: #{stats.distinct_states} states, depth #{stats.depth}, #{seconds} s"
        )

        :ok

      {:error, violation, _stats} ->
        Mix.shell().error("FAULT  #{name}: #{violation.kind} #{violation[:property] || ""}")

        for {step, index} <- Enum.with_index(violation[:trace] || [], 1) do
          Mix.shell().error("  step #{index}: #{inspect(step, limit: 30)}")
        end

        :error

      other ->
        Mix.shell().error("FAULT  #{name}: #{inspect(other, limit: 30)}")
        :error
    end
  end
end
