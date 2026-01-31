Mox.defmock(Unshackled.LLM.MockClient, for: Unshackled.LLM.ClientBehaviour)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Unshackled.Repo, :manual)
