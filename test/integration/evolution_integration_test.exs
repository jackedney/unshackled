defmodule Unshackled.Integration.EvolutionIntegrationTest do
  use ExUnit.Case, async: false

  alias Unshackled.Evolution.ClaimChangeDetector
  alias Unshackled.Evolution.ClaimTransition
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo
  import Ecto.Query

  @moduletag :integration

  setup do
    {:ok, _pid} = Application.ensure_all_started(:unshackled)

    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Unshackled.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Unshackled.Repo, {:shared, self()})

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkin(Unshackled.Repo)
    end)

    Repo.delete_all(ClaimTransition)
    Repo.delete_all(BlackboardRecord)

    :ok
  end

  describe "evolution system integration" do
    test "latest_change/1 returns nil when no transitions exist" do
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

    test "latest_change/1 returns most recent transition" do
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
        from_cycle: 1,
        to_cycle: 2,
        previous_claim: "First claim",
        new_claim: "Second claim",
        trigger_agent: "explorer",
        trigger_contribution_id: nil,
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 2,
        to_cycle: 3,
        previous_claim: "Second claim",
        new_claim: "Third claim",
        trigger_agent: "critic",
        trigger_contribution_id: nil,
        change_type: "pivot",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      assert {:ok, transition} = ClaimChangeDetector.latest_change(blackboard.id)
      assert transition.to_cycle == 3
      assert transition.change_type == "pivot"
    end

    test "has_changed?/3 returns true when transition exists in range" do
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
        trigger_contribution_id: nil,
        change_type: "refinement",
        diff_additions: %{},
        diff_removals: %{}
      })
      |> Repo.insert()

      assert ClaimChangeDetector.has_changed?(blackboard.id, 0, 5) == true
      assert ClaimChangeDetector.has_changed?(blackboard.id, 2, 4) == true
    end

    test "has_changed?/3 returns false when no transition exists" do
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

    test "has_changed?/3 handles edge cases correctly" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim",
          support_strength: 0.5,
          cycle_count: 3
        })
        |> Repo.insert()

      refute ClaimChangeDetector.has_changed?(blackboard.id, -1, 5)
      refute ClaimChangeDetector.has_changed?(blackboard.id, 1, 1)
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

      transitions_before =
        Repo.all(
          from(ct in ClaimTransition,
            where: ct.blackboard_id == ^blackboard.id
          )
        )

      assert length(transitions_before) == 0

      Process.sleep(100)

      transitions_after =
        Repo.all(
          from(ct in ClaimTransition,
            where: ct.blackboard_id == ^blackboard.id
          )
        )

      assert length(transitions_after) == 0
    end

    test "transition records store correct metadata" do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Updated claim",
          support_strength: 0.5,
          cycle_count: 2
        })
        |> Repo.insert()

      %ClaimTransition{}
      |> ClaimTransition.changeset(%{
        blackboard_id: blackboard.id,
        from_cycle: 1,
        to_cycle: 2,
        previous_claim: "Original claim",
        new_claim: "Updated claim",
        trigger_agent: "connector",
        trigger_contribution_id: 42,
        change_type: "expansion",
        diff_additions: %{"concepts" => ["new concept"]},
        diff_removals: %{"concepts" => ["old concept"]}
      })
      |> Repo.insert()

      transitions =
        Repo.all(
          from(ct in ClaimTransition,
            where: ct.blackboard_id == ^blackboard.id
          )
        )

      assert length(transitions) == 1

      transition = List.first(transitions)
      assert transition.trigger_agent == "connector"
      assert transition.trigger_contribution_id == 42
      assert transition.change_type == "expansion"
      assert is_map(transition.diff_additions)
      assert is_map(transition.diff_removals)
    end
  end
end
