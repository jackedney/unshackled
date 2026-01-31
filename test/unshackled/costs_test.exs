defmodule Unshackled.CostsTest do
  use Unshackled.DataCase, async: true

  alias Unshackled.Costs
  alias Unshackled.Costs.LLMCost
  alias Unshackled.Blackboard.BlackboardRecord

  describe "get_session_total_cost/1" do
    test "returns total cost for session with multiple cost records" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.001)
      insert_cost(blackboard.id, 1, "critic", "openai/gpt-4", 75, 25, 0.0007)
      insert_cost(blackboard.id, 2, "explorer", "openai/gpt-4", 150, 100, 0.002)

      total = Costs.get_session_total_cost(blackboard.id)
      assert_in_delta total, 0.0037, 0.00001
    end

    test "returns 0.0 for session with no cost records" do
      {:ok, blackboard} = create_blackboard()

      total = Costs.get_session_total_cost(blackboard.id)
      assert total == 0.0
    end

    test "returns 0.0 for non-existent session" do
      total = Costs.get_session_total_cost(999)
      assert total == 0.0
    end

    test "returns accurate sum for single cost record" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.00234)

      total = Costs.get_session_total_cost(blackboard.id)
      assert_in_delta total, 0.00234, 0.00001
    end

    test "returns 0.0 for zero cost records" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 0, 0, 0.0)
      insert_cost(blackboard.id, 2, "critic", "openai/gpt-4", 0, 0, 0.0)

      total = Costs.get_session_total_cost(blackboard.id)
      assert total == 0.0
    end

    test "handles floating point precision correctly" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.0001)
      insert_cost(blackboard.id, 2, "explorer", "openai/gpt-4", 100, 50, 0.0002)
      insert_cost(blackboard.id, 3, "explorer", "openai/gpt-4", 100, 50, 0.0003)

      total = Costs.get_session_total_cost(blackboard.id)
      assert_in_delta total, 0.0006, 0.00001
    end
  end

  describe "get_cost_by_cycle/1" do
    test "returns cost breakdown by cycle sorted descending" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.001)
      insert_cost(blackboard.id, 1, "critic", "openai/gpt-4", 50, 25, 0.0005)
      insert_cost(blackboard.id, 2, "explorer", "openai/gpt-4", 150, 100, 0.002)
      insert_cost(blackboard.id, 3, "explorer", "openai/gpt-4", 200, 100, 0.003)

      result = Costs.get_cost_by_cycle(blackboard.id)

      assert length(result) == 3
      assert Enum.at(result, 0).cycle_number == 3
      assert Enum.at(result, 0).total_cost == 0.003
      assert Enum.at(result, 0).total_tokens == 300

      assert Enum.at(result, 1).cycle_number == 2
      assert Enum.at(result, 1).total_cost == 0.002
      assert Enum.at(result, 1).total_tokens == 250

      assert Enum.at(result, 2).cycle_number == 1
      assert Enum.at(result, 2).total_cost == 0.0015
      assert Enum.at(result, 2).total_tokens == 225
    end

    test "returns empty list for session with no cost records" do
      {:ok, blackboard} = create_blackboard()

      result = Costs.get_cost_by_cycle(blackboard.id)
      assert result == []
    end

    test "returns empty list for non-existent session" do
      result = Costs.get_cost_by_cycle(999)
      assert result == []
    end

    test "aggregates multiple agents in same cycle" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.001)
      insert_cost(blackboard.id, 1, "critic", "openai/gpt-4", 75, 25, 0.0007)
      insert_cost(blackboard.id, 1, "cartographer", "openai/gpt-4", 50, 50, 0.0008)

      result = Costs.get_cost_by_cycle(blackboard.id)

      assert length(result) == 1
      assert Enum.at(result, 0).cycle_number == 1
      assert Enum.at(result, 0).total_cost == 0.0025
      assert Enum.at(result, 0).total_tokens == 350
    end

    test "correctly calculates total_tokens" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.001)

      result = Costs.get_cost_by_cycle(blackboard.id)

      assert Enum.at(result, 0).total_tokens == 150
    end
  end

  describe "get_cost_by_agent/1" do
    test "returns cost breakdown by agent sorted by total_cost descending" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.001)
      insert_cost(blackboard.id, 2, "explorer", "openai/gpt-4", 150, 100, 0.002)
      insert_cost(blackboard.id, 1, "critic", "openai/gpt-4", 75, 25, 0.0007)
      insert_cost(blackboard.id, 3, "cartographer", "openai/gpt-4", 50, 50, 0.0008)

      result = Costs.get_cost_by_agent(blackboard.id)

      assert length(result) == 3

      assert Enum.at(result, 0).agent_role == "explorer"
      assert Enum.at(result, 0).total_cost == 0.003
      assert Enum.at(result, 0).call_count == 2

      assert Enum.at(result, 1).agent_role == "cartographer"
      assert Enum.at(result, 1).total_cost == 0.0008
      assert Enum.at(result, 1).call_count == 1

      assert Enum.at(result, 2).agent_role == "critic"
      assert Enum.at(result, 2).total_cost == 0.0007
      assert Enum.at(result, 2).call_count == 1
    end

    test "returns empty list for session with no cost records" do
      {:ok, blackboard} = create_blackboard()

      result = Costs.get_cost_by_agent(blackboard.id)
      assert result == []
    end

    test "returns empty list for non-existent session" do
      result = Costs.get_cost_by_agent(999)
      assert result == []
    end

    test "correctly counts calls per agent across cycles" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 100, 50, 0.001)
      insert_cost(blackboard.id, 2, "explorer", "openai/gpt-4", 150, 100, 0.002)
      insert_cost(blackboard.id, 3, "explorer", "openai/gpt-4", 200, 100, 0.003)
      insert_cost(blackboard.id, 1, "critic", "openai/gpt-4", 75, 25, 0.0007)

      result = Costs.get_cost_by_agent(blackboard.id)

      explorer = Enum.find(result, fn r -> r.agent_role == "explorer" end)
      assert explorer.call_count == 3
      assert explorer.total_cost == 0.006

      critic = Enum.find(result, fn r -> r.agent_role == "critic" end)
      assert critic.call_count == 1
      assert critic.total_cost == 0.0007
    end

    test "handles agents with zero cost" do
      {:ok, blackboard} = create_blackboard()

      insert_cost(blackboard.id, 1, "explorer", "openai/gpt-4", 0, 0, 0.0)
      insert_cost(blackboard.id, 2, "critic", "openai/gpt-4", 0, 0, 0.0)

      result = Costs.get_cost_by_agent(blackboard.id)

      assert length(result) == 2

      explorer = Enum.find(result, fn r -> r.agent_role == "explorer" end)
      assert explorer.total_cost == 0.0
      assert explorer.call_count == 1

      critic = Enum.find(result, fn r -> r.agent_role == "critic" end)
      assert critic.total_cost == 0.0
      assert critic.call_count == 1
    end
  end

  defp create_blackboard do
    attrs = %{
      current_claim: "Test claim",
      support_strength: 0.5
    }

    %BlackboardRecord{}
    |> BlackboardRecord.changeset(attrs)
    |> Unshackled.Repo.insert()
  end

  defp insert_cost(
         blackboard_id,
         cycle_number,
         agent_role,
         model_used,
         input_tokens,
         output_tokens,
         cost_usd
       ) do
    attrs = %{
      blackboard_id: blackboard_id,
      cycle_number: cycle_number,
      agent_role: agent_role,
      model_used: model_used,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: cost_usd
    }

    %LLMCost{}
    |> LLMCost.changeset(attrs)
    |> Unshackled.Repo.insert()
  end
end
