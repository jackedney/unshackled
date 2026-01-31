defmodule Unshackled.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Unshackled.Repo,
      {Phoenix.PubSub, name: Unshackled.PubSub},
      Unshackled.Embedding.ModelServer,
      Unshackled.Embedding.Space,
      Unshackled.Agents.Supervisor,
      Unshackled.Session,
      UnshackledWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Unshackled.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
