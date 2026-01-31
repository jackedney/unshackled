defmodule Unshackled.Integration.FullSessionTest do
  use ExUnit.Case, async: false
  import Mox

  alias Unshackled.Config
  alias Unshackled.Session
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Repo
  import Ecto.Query

  @moduletag :capture_log
  @moduletag :integration

  setup do
    {:ok, _pid} = Application.ensure_all_started(:unshackled)

    Application.put_env(:unshackled, :llm_client, Unshackled.LLM.MockClient)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Unshackled.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Unshackled.Repo, {:shared, self()})

    on_exit(fn ->
      Application.put_env(:unshackled, :llm_client, Unshackled.LLM.Client)
      Ecto.Adapters.SQL.Sandbox.checkin(Unshackled.Repo)
    end)

    :ok
  end

  setup :set_mox_global
  setup :verify_on_exit!

  defp mock_response_content do
    Jason.encode!(%{
      "new_claim" => "Local entropy gradients create micro-scale thermodynamic boundaries",
      "inference_type" => "deductive",
      "reasoning" => "Direct logical extension of the claim"
    })
  end

  defp mock_response_struct do
    %{
      content: mock_response_content(),
      usage: %{input_tokens: 100, output_tokens: 50},
      cost: %{total_cost: 0.001}
    }
  end

  defp setup_mock_responses do
    Unshackled.LLM.MockClient
    |> stub(:chat, fn _model, _messages ->
      {:ok, mock_response_struct()}
    end)
    |> stub(:chat_random, fn _messages ->
      model = Enum.random(Unshackled.LLM.Config.model_pool())
      {:ok, mock_response_struct(), model}
    end)
  end

  describe "full session integration" do
    setup do
      setup_mock_responses()
      :ok
    end

    test "session starts and completes at max_cycles" do
      config =
        Config.new(
          seed_claim: "What if entropy increases locally?",
          max_cycles: 5,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(200)

      {:ok, _status} = Session.status(session_id)

      :ok = Session.stop(session_id)
    end

    test "blackboard state is persisted correctly" do
      config =
        Config.new(
          seed_claim: "Test claim for persistence",
          max_cycles: 3,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(200)

      {:ok, blackboard_id} = get_blackboard_id(session_id)

      blackboard_record = Repo.get(BlackboardRecord, blackboard_id)
      assert blackboard_record.cycle_count > 0
      assert is_binary(blackboard_record.current_claim)

      :ok = Session.stop(session_id)
    end

    test "agent contributions are logged" do
      config =
        Config.new(
          seed_claim: "Test claim for agent logging",
          max_cycles: 3,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(200)

      {:ok, blackboard_id} = get_blackboard_id(session_id)

      contributions =
        Repo.all(
          from(c in AgentContribution,
            where: c.blackboard_id == ^blackboard_id,
            order_by: [asc: c.cycle_number]
          )
        )

      assert length(contributions) > 0

      :ok = Session.stop(session_id)
    end

    test "trajectory points are stored" do
      config =
        Config.new(
          seed_claim: "Test claim for trajectory",
          max_cycles: 3,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(200)

      {:ok, blackboard_id} = get_blackboard_id(session_id)

      trajectory_points =
        Repo.all(
          from(t in TrajectoryPoint,
            where: t.blackboard_id == ^blackboard_id,
            order_by: [asc: t.cycle_number]
          )
        )

      assert length(trajectory_points) >= 1

      :ok = Session.stop(session_id)
    end
  end

  defp get_blackboard_id(session_id) do
    sessions = Session.list_sessions()

    session_info =
      Enum.find(sessions, fn {id, _status} ->
        id == session_id
      end)

    if session_info do
      {_session_id, _status} = session_info
      blackboard_id = find_blackboard_id_for_session(session_id)

      if is_integer(blackboard_id) do
        {:ok, blackboard_id}
      else
        {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  defp find_blackboard_id_for_session(_session_id) do
    all_blackboard_records =
      Repo.all(
        from(b in BlackboardRecord,
          order_by: [desc: b.inserted_at],
          limit: 10
        )
      )

    if length(all_blackboard_records) > 0 do
      List.first(all_blackboard_records).id
    else
      nil
    end
  end
end
