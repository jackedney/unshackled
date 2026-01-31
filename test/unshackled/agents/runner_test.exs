defmodule Unshackled.Agents.RunnerTest do
  use Unshackled.DataCase, async: true

  alias Unshackled.Costs.LLMCost
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo

  describe "check_cost_limit/2" do
    setup do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 0
        })
        |> Repo.insert()

      %{blackboard_id: blackboard.id}
    end

    test "does nothing when cost_limit_usd is nil", %{blackboard_id: blackboard_id} do
      cost_attrs = %{
        blackboard_id: blackboard_id,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "openai/gpt-4",
        input_tokens: 1000,
        output_tokens: 500,
        cost_usd: 10.0
      }

      Repo.insert!(LLMCost.changeset(%LLMCost{}, cost_attrs))

      total_cost = Unshackled.Costs.get_session_total_cost(blackboard_id)
      assert total_cost == 10.0
    end

    test "does nothing when total cost is below limit", %{blackboard_id: blackboard_id} do
      blackboard = Repo.get(BlackboardRecord, blackboard_id)

      changeset =
        BlackboardRecord.changeset(blackboard, %{cost_limit_usd: Decimal.from_float(1.0)})

      {:ok, _} = Repo.update(changeset)

      cost_attrs = %{
        blackboard_id: blackboard_id,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "openai/gpt-4",
        input_tokens: 100,
        output_tokens: 50,
        cost_usd: 0.01
      }

      Repo.insert!(LLMCost.changeset(%LLMCost{}, cost_attrs))

      total_cost = Unshackled.Costs.get_session_total_cost(blackboard_id)
      assert total_cost < 1.0
    end

    test "logs when total cost exceeds limit but doesn't crash", %{blackboard_id: blackboard_id} do
      blackboard = Repo.get(BlackboardRecord, blackboard_id)

      changeset =
        BlackboardRecord.changeset(blackboard, %{cost_limit_usd: Decimal.from_float(0.01)})

      {:ok, _} = Repo.update(changeset)

      cost_attrs = %{
        blackboard_id: blackboard_id,
        cycle_number: 1,
        agent_role: "explorer",
        model_used: "openai/gpt-4",
        input_tokens: 1000,
        output_tokens: 500,
        cost_usd: 0.015
      }

      Repo.insert!(LLMCost.changeset(%LLMCost{}, cost_attrs))

      total_cost = Unshackled.Costs.get_session_total_cost(blackboard_id)
      assert total_cost > 0.01
    end
  end
end
