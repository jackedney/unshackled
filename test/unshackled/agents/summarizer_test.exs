defmodule Unshackled.Agents.SummarizerTest do
  use UnshackledWeb.ConnCase, async: false

  alias Unshackled.Agents.Summarizer
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Blackboard.BlackboardSnapshot
  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Evolution.ClaimSummary
  alias Unshackled.Repo

  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    Application.put_env(:unshackled, :llm_client, Unshackled.LLM.MockClient)

    on_exit(fn ->
      Application.put_env(:unshackled, :llm_client, Unshackled.LLM.Client)
    end)

    :ok
  end

  setup do
    Repo.delete_all(ClaimSummary)
    Repo.delete_all(AgentContribution)
    Repo.delete_all(BlackboardSnapshot)
    Repo.delete_all(BlackboardRecord)
    :ok
  end

  describe "summarize/1" do
    test "returns error for invalid blackboard_id" do
      assert {:error, :blackboard_not_found} = Summarizer.summarize(999_999)
    end

    test "returns error when blackboard has no snapshots" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      assert {:error, :no_claims} = Summarizer.summarize(blackboard.id)
    end

    test "generates summary successfully for valid blackboard with snapshots" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Consequently, their long-term competitive advantage erodes.",
          support_strength: 0.6,
          cycle_count: 5
        })
        |> Repo.insert()

      # Create snapshots within the context window (last 5 cycles: 1-5)
      %BlackboardSnapshot{}
      |> BlackboardSnapshot.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        state_json: %{
          "current_claim" => "Companies not adopting AI will fall behind competitors."
        }
      })
      |> Repo.insert()

      %BlackboardSnapshot{}
      |> BlackboardSnapshot.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 5,
        state_json: %{
          "current_claim" => "Consequently, their long-term competitive advantage erodes."
        }
      })
      |> Repo.insert()

      mock_summary_response = ~s({
        "full_context_summary": "Companies that choose not to invest in AI technologies will experience erosion of their long-term competitive advantage.",
        "evolution_narrative": "The claim evolved from a general warning about non-adoption to a specific prediction about competitive advantage erosion.",
        "addressed_objections": ["objection 1"],
        "remaining_gaps": ["gap 1"]
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_summary_response}}
      end)

      assert {:ok, summary} = Summarizer.summarize(blackboard.id)

      assert is_binary(summary.full_context_summary)
      assert is_binary(summary.evolution_narrative)
      assert is_map(summary.addressed_objections)
      assert is_map(summary.remaining_gaps)
      assert summary.blackboard_id == blackboard.id
      assert summary.cycle_number == 5
    end

    test "handles LLM client errors gracefully" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      # Snapshot at cycle 1 to be within context window (min_cycle = max(1, 1-5+1) = 1)
      %BlackboardSnapshot{}
      |> BlackboardSnapshot.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        state_json: %{"current_claim" => "Original claim"}
      })
      |> Repo.insert()

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Summarizer.summarize(blackboard.id)
    end

    test "normalizes response lists to remove empty strings" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      # Snapshot at cycle 1 to be within context window
      %BlackboardSnapshot{}
      |> BlackboardSnapshot.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        state_json: %{"current_claim" => "Original claim"}
      })
      |> Repo.insert()

      # Use arrays instead of objects since parse_summary_response expects lists
      mock_summary_response = ~s({
        "full_context_summary": "Test summary",
        "evolution_narrative": "Test narrative",
        "addressed_objections": ["valid objection", "", "another objection"],
        "remaining_gaps": ["valid gap", "  "]
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_summary_response}}
      end)

      assert {:ok, summary} = Summarizer.summarize(blackboard.id)

      assert is_map(summary.addressed_objections)
      assert is_map(summary.remaining_gaps)

      addressed_values = Map.values(summary.addressed_objections)
      gaps_values = Map.values(summary.remaining_gaps)

      assert Enum.all?(addressed_values, &(is_binary(&1) and String.length(&1) > 0))
      assert Enum.all?(gaps_values, &(is_binary(&1) and String.length(&1) > 0))
    end

    test "handles invalid LLM response format" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      # Snapshot at cycle 1 to be within context window
      %BlackboardSnapshot{}
      |> BlackboardSnapshot.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        state_json: %{"current_claim" => "Original claim"}
      })
      |> Repo.insert()

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: "This is not valid JSON"}}
      end)

      assert {:error, :invalid_summary_response_format} = Summarizer.summarize(blackboard.id)
    end
  end

  describe "get_latest_summary/1" do
    test "returns error when no summary exists" do
      assert {:error, :not_found} = Summarizer.get_latest_summary(999_999)
    end

    test "returns the most recent summary when multiple exist" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      {:ok, _} =
        %ClaimSummary{}
        |> ClaimSummary.changeset(%{
          blackboard_id: blackboard.id,
          cycle_number: 3,
          full_context_summary: "Summary at cycle 3",
          evolution_narrative: "Narrative 3",
          addressed_objections: %{},
          remaining_gaps: %{}
        })
        |> Repo.insert()

      {:ok, _} =
        %ClaimSummary{}
        |> ClaimSummary.changeset(%{
          blackboard_id: blackboard.id,
          cycle_number: 5,
          full_context_summary: "Summary at cycle 5",
          evolution_narrative: "Narrative 5",
          addressed_objections: %{},
          remaining_gaps: %{}
        })
        |> Repo.insert()

      assert {:ok, summary} = Summarizer.get_latest_summary(blackboard.id)
      assert summary.cycle_number == 5
      assert summary.full_context_summary == "Summary at cycle 5"
    end

    test "returns summary when only one exists" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      {:ok, _} =
        %ClaimSummary{}
        |> ClaimSummary.changeset(%{
          blackboard_id: blackboard.id,
          cycle_number: 1,
          full_context_summary: "Only summary",
          evolution_narrative: "Only narrative",
          addressed_objections: %{},
          remaining_gaps: %{}
        })
        |> Repo.insert()

      assert {:ok, summary} = Summarizer.get_latest_summary(blackboard.id)
      assert summary.full_context_summary == "Only summary"
    end
  end
end
