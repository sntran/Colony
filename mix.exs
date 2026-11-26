defmodule Colony.MixProject do
  use Mix.Project

  def project do
    [
      app: :colony,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Colony.Application, []},
      extra_applications: [:logger]
    ]
  end

  # The server uses only Erlang and Elixir. Do not add a package that has a NIF or a port.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.15"}
    ]
  end
end
