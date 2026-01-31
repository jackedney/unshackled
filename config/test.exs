import Config

config :unshackled, Unshackled.Repo,
  database: Path.expand("priv/unshackled_test.db", Path.dirname(__DIR__)),
  pool_size: System.schedulers_online() * 2,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :unshackled, UnshackledWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_security",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning
