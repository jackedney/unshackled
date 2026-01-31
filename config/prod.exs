import Config

config :unshackled, Unshackled.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

# Note: Do not include the server option here, it is handled
# by runtime.exs for production deployments.
#
# For production, we configure the host and port from environment variables.
# The secret_key_base is also configured in runtime.exs.
config :unshackled, UnshackledWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# environment variables, is done in runtime.exs.
