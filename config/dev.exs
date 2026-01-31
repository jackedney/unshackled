import Config

# For development, we disable any cache and enable
# debugging and code reloading.
config :unshackled, UnshackledWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "YPjEn8mNq2rKvL5wX7cB4fD6gH9iJ1kM3oT8sU0wZ2yA4bC5dE6fG7hI8jK9lL0n",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:unshackled, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:unshackled, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :unshackled, UnshackledWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/unshackled_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]
