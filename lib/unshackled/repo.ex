defmodule Unshackled.Repo do
  use Ecto.Repo,
    otp_app: :unshackled,
    adapter: Ecto.Adapters.SQLite3
end
