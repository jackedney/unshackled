defmodule UnshackledWeb.SessionsLive.ShowTimelineMobileTest do
  use UnshackledWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Unshackled.Evolution.ClaimTransition
  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo

  setup do
    Repo.delete_all(ClaimTransition)
    Repo.delete_all(BlackboardRecord)
    :ok
  end

  describe "Evolution Timeline mobile responsiveness" do
    test "renders responsive timeline card", %{conn: conn} do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim for mobile",
          support_strength: 0.6,
          cycle_count: 3
        })
        |> Repo.insert()

      {:ok, _transition} =
        %ClaimTransition{}
        |> ClaimTransition.changeset(%{
          blackboard_id: blackboard.id,
          from_cycle: 1,
          to_cycle: 3,
          previous_claim: "Original claim",
          new_claim:
            "Modified claim for mobile with some text that makes it longer to test truncation",
          trigger_agent: "explorer",
          trigger_contribution_id: nil,
          change_type: "expansion",
          diff_additions: %{},
          diff_removals: %{}
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, "/sessions/#{blackboard.id}")

      assert html =~ "Claim Evolution"
      assert html =~ "Cycle 3"
      assert html =~ "Expanded"
      # Mobile stacked cards layout uses md:hidden, desktop timeline uses hidden md:block
      assert html =~ "md:hidden"
      assert html =~ "hidden md:block"
      assert html =~ "line-clamp-2"
      assert html =~ "Show more"
      assert html =~ "active:scale-[0.99]"
    end
  end
end
