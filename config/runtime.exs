import Config

if config_env() != :test do
  port = String.to_integer(System.get_env("PORT") || "4000")

  # This prototype has no accounts and signs nothing that must stay after a restart.
  # Thus a new random key at each start is sufficient.
  secret =
    System.get_env("SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(48))

  config :colony, ColonyWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret
end

# Optional values from the environment. They change the game config for one run.
overrides =
  [
    workers: System.get_env("COLONY_WORKERS"),
    seed: System.get_env("COLONY_SEED")
  ]
  |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  |> Enum.map(fn {key, value} -> {key, String.to_integer(value)} end)

overrides =
  case System.get_env("COLONY_SAVE_FILE") do
    value when value in [nil, ""] -> overrides
    value -> [{:save_file, value} | overrides]
  end

if overrides != [] do
  config :colony, :game, Keyword.merge(Application.get_env(:colony, :game, []), overrides)
end
