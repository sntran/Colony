import Config

config :phoenix, :json_library, JSON

config :colony, ColonyWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: Colony.PubSub

config :logger, :default_formatter, format: "$time [$level] $message\n"

import_config "game.exs"
import_config "#{config_env()}.exs"
