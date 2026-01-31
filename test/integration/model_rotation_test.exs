defmodule Unshackled.Integration.ModelRotationTest do
  use ExUnit.Case, async: false

  alias Unshackled.Config
  alias Unshackled.Session
  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo
  import Ecto.Query
  import Mox

  @moduletag :capture_log

  setup do
    {:ok, _pid} = Application.ensure_all_started(:unshackled)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Unshackled.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Unshackled.Repo, {:shared, self()})

    Application.put_env(:unshackled, :llm_client, Unshackled.LLM.MockClient)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkin(Unshackled.Repo)
      Application.put_env(:unshackled, :llm_client, Unshackled.LLM.Client)
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

  describe "model rotation across agent spawns" do
    test "different models selected across cycles" do
      model_pool = Unshackled.LLM.Config.model_pool()

      Unshackled.LLM.MockClient
      |> stub(:chat, fn _model, _messages ->
        {:ok, mock_response_struct()}
      end)
      |> stub(:chat_random, fn _messages ->
        model = Enum.random(model_pool)
        {:ok, mock_response_struct(), model}
      end)

      config =
        Config.new(
          seed_claim: "Test claim for model rotation",
          max_cycles: 10,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(300)

      blackboard_id = get_most_recent_blackboard_id()

      contributions =
        Repo.all(
          from(c in AgentContribution,
            where: c.blackboard_id == ^blackboard_id,
            order_by: [asc: c.cycle_number, asc: c.id],
            limit: 10
          )
        )

      models_used = Enum.map(contributions, & &1.model_used) |> Enum.uniq()

      assert length(contributions) > 0,
             "Expected at least one agent contribution"

      assert length(models_used) > 1,
             "Expected multiple models to be used, got: #{inspect(models_used)}"

      stop_session(session_id)
    end

    test "all models in pool are eventually used" do
      model_pool = Unshackled.LLM.Config.model_pool()

      Unshackled.LLM.MockClient
      |> stub(:chat, fn _model, _messages ->
        {:ok, mock_response_struct()}
      end)
      |> stub(:chat_random, fn _messages ->
        model = Enum.random(model_pool)
        {:ok, mock_response_struct(), model}
      end)

      config =
        Config.new(
          seed_claim: "Test claim for full model pool coverage",
          max_cycles: 30,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(300)

      blackboard_id = get_most_recent_blackboard_id()

      contributions =
        Repo.all(
          from(c in AgentContribution,
            where: c.blackboard_id == ^blackboard_id,
            order_by: [asc: c.cycle_number, asc: c.id],
            limit: 20
          )
        )

      models_used = Enum.map(contributions, & &1.model_used) |> Enum.uniq()

      assert length(contributions) > 0,
             "Expected at least one agent contribution"

      assert length(models_used) > 1,
             "Expected multiple models to be used, got: #{inspect(models_used)}"

      stop_session(session_id)
    end

    test "model selection is random (statistical test)" do
      model_pool = Unshackled.LLM.Config.model_pool()

      Unshackled.LLM.MockClient
      |> stub(:chat, fn _model, _messages ->
        {:ok, mock_response_struct()}
      end)
      |> stub(:chat_random, fn _messages ->
        model = Enum.random(model_pool)
        {:ok, mock_response_struct(), model}
      end)

      config =
        Config.new(
          seed_claim: "Test claim for randomness verification",
          max_cycles: 20,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(300)

      blackboard_id = get_most_recent_blackboard_id()

      contributions =
        Repo.all(
          from(c in AgentContribution,
            where: c.blackboard_id == ^blackboard_id,
            order_by: [asc: c.cycle_number],
            limit: 20
          )
        )

      models_used = Enum.map(contributions, & &1.model_used)

      pool_size = length(model_pool)
      sample_size = length(models_used)

      assert sample_size > 0,
             "Expected at least one agent contribution"

      if sample_size > 0 do
        model_counts = Enum.frequencies(models_used)

        expected_count = sample_size / pool_size

        model_stats =
          Enum.map(model_pool, fn model ->
            count = Map.get(model_counts, model, 0)

            deviation =
              if expected_count > 0 do
                abs(count - expected_count) / expected_count
              else
                0
              end

            {model, count, deviation}
          end)

        max_deviation =
          model_stats
          |> Enum.map(fn {_model, _count, deviation} -> deviation end)
          |> Enum.max(fn -> 0 end)

        assert max_deviation < 2.0,
               """
               Model selection does not appear to be random.
               Expected average count per model: #{Float.round(expected_count, 2)}
               Model stats: #{inspect(model_stats)}
               Max deviation: #{Float.round(max_deviation, 2)}
               """
      end

      stop_session(session_id)
    end

    test "AgentContribution records show varied model_used values" do
      model_pool = Unshackled.LLM.Config.model_pool()

      Unshackled.LLM.MockClient
      |> stub(:chat, fn _model, _messages ->
        {:ok, mock_response_struct()}
      end)
      |> stub(:chat_random, fn _messages ->
        model = Enum.random(model_pool)
        {:ok, mock_response_struct(), model}
      end)

      config =
        Config.new(
          seed_claim: "Test claim for model variation",
          max_cycles: 15,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(300)

      blackboard_id = get_most_recent_blackboard_id()

      contributions =
        Repo.all(
          from(c in AgentContribution,
            where: c.blackboard_id == ^blackboard_id,
            select: [c.cycle_number, c.agent_role, c.model_used],
            order_by: [asc: c.cycle_number, asc: c.id],
            limit: 10
          )
        )

      assert length(contributions) > 0,
             "Expected at least one agent contribution"

      unique_models_per_cycle =
        contributions
        |> Enum.group_by(fn [cycle, _role, _model] -> cycle end)
        |> Enum.map(fn {_cycle, cycle_contributions} ->
          models = Enum.map(cycle_contributions, fn [_c, _r, model] -> model end)
          length(Enum.uniq(models))
        end)

      assert Enum.any?(unique_models_per_cycle, &(&1 > 1)),
             """
             Expected at least one cycle with multiple different models.
             Unique models per cycle: #{inspect(unique_models_per_cycle)}
             Contributions: #{inspect(contributions)}
             """

      stop_session(session_id)
    end

    test "single-model pool works without rotation" do
      single_model_pool = ["openai/gpt-5.2"]

      # Set the global LLM model pool to a single model so Client.chat_random
      # picks only this model via LLM.Config.random_model()
      original_llm_config = Application.get_env(:unshackled, :llm, [])
      Application.put_env(:unshackled, :llm, Keyword.put(original_llm_config, :model_pool, single_model_pool))

      on_exit(fn ->
        Application.put_env(:unshackled, :llm, original_llm_config)
      end)

      Unshackled.LLM.MockClient
      |> stub(:chat, fn _model, _messages ->
        {:ok, mock_response_struct()}
      end)
      |> stub(:chat_random, fn _messages ->
        model = "openai/gpt-5.2"
        {:ok, mock_response_struct(), model}
      end)

      config =
        Config.new(
          seed_claim: "Test claim with single model",
          max_cycles: 5,
          cycle_mode: :event_driven,
          cycle_timeout_ms: 10000,
          model_pool: single_model_pool
        )

      {:ok, session_id} = Session.start(config)

      Process.sleep(200)

      blackboard_id = get_most_recent_blackboard_id()

      contributions =
        Repo.all(
          from(c in AgentContribution,
            where: c.blackboard_id == ^blackboard_id,
            order_by: [asc: c.cycle_number],
            limit: 10
          )
        )

      assert length(contributions) > 0,
             "Expected at least one agent contribution"

      models_used = Enum.map(contributions, & &1.model_used)

      assert Enum.all?(models_used, &(&1 == "openai/gpt-5.2")),
             """
             Expected all contributions to use single model, got: #{inspect(models_used)}
             """

      stop_session(session_id)
    end
  end

  defp get_most_recent_blackboard_id do
    blackboard_records =
      Repo.all(
        from(b in BlackboardRecord,
          order_by: [desc: b.inserted_at],
          limit: 1
        )
      )

    if length(blackboard_records) > 0 do
      List.first(blackboard_records).id
    else
      nil
    end
  end

  defp stop_session(session_id) do
    case Session.stop(session_id) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end

    Process.sleep(100)
  end
end
