import Config

# The tests run the world with no server process and no browser.
config :colony, ColonyWeb.Endpoint, http: [ip: {127, 0, 0, 1}, port: 4002], server: false
config :colony, start_world: false
config :logger, level: :warning
