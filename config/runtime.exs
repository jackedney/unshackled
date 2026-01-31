import Config

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/unshackled/unshackled.db
      """

  config :unshackled, Unshackled.Repo, database: database_path

  # The secret_key_base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :unshackled, UnshackledWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end

if config_env() != :test do
  if config_env() == :prod do
    openrouter_api_key =
      System.get_env("OPENROUTER_API_KEY") ||
        raise """
        environment variable OPENROUTER_API_KEY is missing.
        This is required for the application to function in production.
        Set it in docker-compose.yml or as an environment variable.
        """

    config :ex_llm,
      api_key: openrouter_api_key,
      provider: :openrouter
  else
    openrouter_api_key = System.get_env("OPENROUTER_API_KEY")

    if openrouter_api_key do
      config :ex_llm,
        api_key: openrouter_api_key
    end
  end
end
