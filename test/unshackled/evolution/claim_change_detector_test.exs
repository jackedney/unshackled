defmodule Unshackled.Evolution.ClaimChangeDetectorTest do
  use UnshackledWeb.ConnCase, async: false

  alias Unshackled.Evolution.ClaimChangeDetector
  alias Unshackled.Evolution.ClaimTransition
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Embedding.TrajectoryPoint
  alias Unshackled.Agents.AgentContribution
  alias Unshackled.Repo
  import Ecto.Query

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
    Repo.delete_all(ClaimTransition)
    Repo.delete_all(AgentContribution)
    Repo.delete_all(TrajectoryPoint)
    Repo.delete_all(BlackboardRecord)
    :ok
  end

  describe "detect_changes/1" do
    test "returns error for invalid blackboard_id" do
      assert {:error, :invalid_blackboard_id} = ClaimChangeDetector.detect_changes(nil)
      assert {:error, :invalid_blackboard_id} = ClaimChangeDetector.detect_changes(0)
      assert {:error, :invalid_blackboard_id} = ClaimChangeDetector.detect_changes(-1)
    end

    test "returns error when blackboard has no trajectory points" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      assert {:error, :no_trajectory_points} = ClaimChangeDetector.detect_changes(blackboard.id)
    end

    test "returns empty list when only one trajectory point exists" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 0,
        claim_text: "AI is powerful",
        support_strength: 0.5,
        embedding_vector: Nx.tensor([0.1, 0.2, 0.3]) |> Nx.to_binary()
      })
      |> Repo.insert()

      assert {:ok, []} = ClaimChangeDetector.detect_changes(blackboard.id)
    end

    test "detects no change when similarity is above threshold" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 2
        })
        |> Repo.insert()

      embedding = :erlang.term_to_binary(Nx.tensor([0.1, 0.2, 0.3]))

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 0,
        claim_text: "AI is powerful",
        support_strength: 0.5,
        embedding_vector: embedding
      })
      |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        claim_text: "AI is very powerful",
        support_strength: 0.55,
        embedding_vector: embedding
      })
      |> Repo.insert()

      {:ok, transitions} = ClaimChangeDetector.detect_changes(blackboard.id)
      assert transitions == []
    end

    test "detects and creates transition when similarity is below threshold" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Companies not adopting AI will lose competitive advantage",
          support_strength: 0.6,
          cycle_count: 2
        })
        |> Repo.insert()

      embedding1 = :erlang.term_to_binary(Nx.tensor([0.1, 0.2, 0.3]))
      embedding2 = :erlang.term_to_binary(Nx.tensor([0.9, 0.8, 0.7]))

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 0,
        claim_text: "AI will transform business",
        support_strength: 0.5,
        embedding_vector: embedding1
      })
      |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        claim_text: "Companies not adopting AI will lose competitive advantage",
        support_strength: 0.6,
        embedding_vector: embedding2
      })
      |> Repo.insert()

      mock_diff_response = ~s({
        "additions": ["competitive advantage", "companies", "non-adoption consequence"],
        "removals": ["general transformation"],
        "modifications": ["AI focus"]
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: "refinement"}}
      end)
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      {:ok, transitions} = ClaimChangeDetector.detect_changes(blackboard.id)

      assert is_list(transitions)
      assert length(transitions) > 0
    end

    test "example: claim change from 'A' to 'B' creates transition record" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "B",
          support_strength: 0.5,
          cycle_count: 2
        })
        |> Repo.insert()

      embedding_a = :erlang.term_to_binary(Nx.tensor([0.1, 0.2, 0.3]))
      embedding_b = :erlang.term_to_binary(Nx.tensor([0.9, 0.8, 0.7]))

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 0,
        claim_text: "A",
        support_strength: 0.5,
        embedding_vector: embedding_a
      })
      |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        claim_text: "B",
        support_strength: 0.5,
        embedding_vector: embedding_b
      })
      |> Repo.insert()

      mock_diff_response = ~s({
        "additions": ["B"],
        "removals": ["A"],
        "modifications": []
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: "pivot"}}
      end)
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      {:ok, transitions} = ClaimChangeDetector.detect_changes(blackboard.id)

      assert is_list(transitions)
      assert length(transitions) > 0
    end

    test "negative case: identical claims do not create transition" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Same claim",
          support_strength: 0.5,
          cycle_count: 2
        })
        |> Repo.insert()

      embedding = :erlang.term_to_binary(Nx.tensor([0.1, 0.2, 0.3]))

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 0,
        claim_text: "Same claim",
        support_strength: 0.5,
        embedding_vector: embedding
      })
      |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        claim_text: "Same claim",
        support_strength: 0.5,
        embedding_vector: embedding
      })
      |> Repo.insert()

      {:ok, transitions} = ClaimChangeDetector.detect_changes(blackboard.id)
      assert transitions == []

      db_transitions =
        Repo.all(
          from(ct in ClaimTransition,
            where: ct.blackboard_id == ^blackboard.id
          )
        )

      assert length(db_transitions) == 0
    end

    test "detects multiple transitions in trajectory" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Third claim",
          support_strength: 0.5,
          cycle_count: 3
        })
        |> Repo.insert()

      # Embeddings chosen so consecutive pairs have cosine similarity < 0.95 threshold
      embedding1 = :erlang.term_to_binary(Nx.tensor([0.1, 0.2, 0.3]))
      embedding2 = :erlang.term_to_binary(Nx.tensor([0.9, 0.8, 0.7]))
      embedding3 = :erlang.term_to_binary(Nx.tensor([0.1, -0.5, 0.9]))

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 0,
        claim_text: "First claim",
        support_strength: 0.5,
        embedding_vector: embedding1
      })
      |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 1,
        claim_text: "Second claim",
        support_strength: 0.5,
        embedding_vector: embedding2
      })
      |> Repo.insert()

      %TrajectoryPoint{}
      |> TrajectoryPoint.changeset(%{
        blackboard_id: blackboard.id,
        cycle_number: 2,
        claim_text: "Third claim",
        support_strength: 0.5,
        embedding_vector: embedding3
      })
      |> Repo.insert()

      mock_diff_response = ~s({
        "additions": [],
        "removals": [],
        "modifications": []
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: "pivot"}}
      end)
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: "expansion"}}
      end)
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      {:ok, transitions} = ClaimChangeDetector.detect_changes(blackboard.id)

      assert is_list(transitions)
    end
  end

  describe "latest_change/1" do
    test "returns error for invalid blackboard_id" do
      assert {:error, :invalid_blackboard_id} = ClaimChangeDetector.latest_change(0)
      assert {:error, :invalid_blackboard_id} = ClaimChangeDetector.latest_change(-1)
    end

    test "returns nil when no transitions exist" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 1
        })
        |> Repo.insert()

      assert {:ok, nil} = ClaimChangeDetector.latest_change(blackboard.id)
    end

    test "returns most recent transition when multiple exist" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 3
        })
        |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 0,
        to_cycle: 1,
        previous_claim: "First",
        new_claim: "Second",
        trigger_agent: "explorer",
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 1,
        to_cycle: 2,
        previous_claim: "Second",
        new_claim: "Third",
        trigger_agent: "critic",
        change_type: "pivot",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      assert {:ok, latest} = ClaimChangeDetector.latest_change(blackboard.id)
      assert latest.to_cycle == 2
      assert latest.new_claim == "Third"
      assert latest.trigger_agent == "critic"
    end

    test "returns single transition when only one exists" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 2
        })
        |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 0,
        to_cycle: 1,
        previous_claim: "First",
        new_claim: "Second",
        trigger_agent: "explorer",
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      assert {:ok, transition} = ClaimChangeDetector.latest_change(blackboard.id)
      assert transition.from_cycle == 0
      assert transition.to_cycle == 1
    end
  end

  describe "has_changed?/3" do
    test "returns false for invalid inputs" do
      refute ClaimChangeDetector.has_changed?(0, 1, 2)
      refute ClaimChangeDetector.has_changed?(-1, 1, 2)
      refute ClaimChangeDetector.has_changed?(1, 2, 1)
    end

    test "returns false when no transitions exist in range" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      refute ClaimChangeDetector.has_changed?(blackboard.id, 0, 5)
    end

    test "returns true when transition exists within range" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 2,
        to_cycle: 3,
        previous_claim: "First",
        new_claim: "Second",
        trigger_agent: "explorer",
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      assert ClaimChangeDetector.has_changed?(blackboard.id, 0, 5)
      assert ClaimChangeDetector.has_changed?(blackboard.id, 2, 4)
    end

    test "returns false when transition exists outside range" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 0,
        to_cycle: 1,
        previous_claim: "First",
        new_claim: "Second",
        trigger_agent: "explorer",
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      refute ClaimChangeDetector.has_changed?(blackboard.id, 2, 5)
    end

    test "handles exact cycle boundaries correctly" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 2,
        to_cycle: 3,
        previous_claim: "First",
        new_claim: "Second",
        trigger_agent: "explorer",
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      assert ClaimChangeDetector.has_changed?(blackboard.id, 2, 3)
      assert ClaimChangeDetector.has_changed?(blackboard.id, 0, 3)
    end
  end
end
