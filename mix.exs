defmodule Unshackled.MixProject do
  use Mix.Project

  def project do
    [
      app: :unshackled,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: [
        unshackled: [
          include_executables_for: [:unix]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Unshackled.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_llm, github: "jackedney/ex_llm", branch: "fix/http-client-response-format"},
      {:nx, "~> 0.7"},
      {:exla, "~> 0.9"},
      {:bumblebee, "~> 0.6"},
      {:scholar, "~> 0.3"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.15"},
      {:jason, "~> 1.4"},

      # Phoenix framework
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:bandit, "~> 1.0"},

      # Assets
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},

      # Testing
      {:floki, "~> 0.36", only: :test},
      {:lazy_html, "~> 0.1", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.create", "ecto.migrate", "assets.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind unshackled", "esbuild unshackled"],
      "assets.deploy": [
        "tailwind unshackled --minify",
        "esbuild unshackled --minify",
        "phx.digest"
      ]
    ]
  end
end
