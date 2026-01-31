import Config

config :unshackled, ecto_repos: [Unshackled.Repo]

config :unshackled, Unshackled.Repo,
  database: Path.expand("priv/unshackled.db", Path.dirname(__DIR__)),
  pool_size: 5,
  foreign_keys: :on

config :unshackled, :evolution,
  similarity_threshold: 0.95,
  summarizer_debounce_cycles: 0,
  summarizer_model: "anthropic/claude-haiku-4.5"

config :unshackled, :session,
  max_cycles: 50,
  cycle_mode: :event_driven,
  cycle_timeout_ms: 300_000,
  model_pool: [
    "openai/gpt-5.2",
    "google/gemini-3-pro",
    "moonshot/kimi-k2.5-thinking",
    "anthropic/claude-opus-4.5",
    "zhipu/glm-4.7",
    "deepseek/deepseek-v3.2",
    "mistralai/mistral-large-latest"
  ],
  novelty_bonus_enabled: true,
  decay_rate: 0.02

# Configures the endpoint
config :unshackled, UnshackledWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: UnshackledWeb.ErrorHTML, json: UnshackledWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Unshackled.PubSub,
  live_view: [signing_salt: "kL7mN9pQ"]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  unshackled: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.0",
  unshackled: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger,
  level: :info,
  truncate: 8192,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ],
  handle_otp_reports: true

config :logger, :console,
  format: "[$level] $time $metadata$message\n",
  metadata: [:module, :function, :pid, :cycle_number, :agent_role],
  colors: [enabled: true]

import_config "#{config_env()}.exs"
