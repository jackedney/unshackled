defmodule UnshackledWeb.DashboardLiveTest do
  use UnshackledWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo

  describe "dashboard page structure" do
    test "renders dashboard page with navigation", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "Dashboard"
      assert has_element?(view, "a", "Start New Session")
      assert has_element?(view, "a", "View Sessions")
    end

    test "has links to sessions pages", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, ~s|a[href="/sessions/new"]|)
      assert has_element?(view, ~s|a[href="/sessions"]|)
    end
  end

  describe "dashboard with blackboard data" do
    setup do
      # Insert a blackboard record to simulate stored session data
      {:ok, blackboard} =
        Repo.insert(%BlackboardRecord{
          current_claim: "Test claim for reasoning",
          support_strength: 0.65,
          cycle_count: 10
        })

      %{blackboard: blackboard}
    end

    test "blackboard data is correctly stored", %{blackboard: blackboard} do
      # Verify the blackboard was inserted correctly
      assert blackboard.current_claim == "Test claim for reasoning"
      assert blackboard.support_strength == 0.65
      assert blackboard.cycle_count == 10
    end

    test "dashboard handles case with no active GenServer session", %{conn: conn} do
      # Dashboard should handle gracefully when Session GenServer has no active sessions
      {:ok, view, html} = live(conn, "/")

      assert html =~ "Dashboard"
      assert has_element?(view, "a", "Start New Session")
      assert has_element?(view, "a", "View Sessions")
    end
  end

  describe "dashboard UI components" do
    test "displays correct navigation", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Dashboard"
      assert html =~ "Start New Session"
      assert html =~ "View Sessions"
    end

    test "subtitle is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Session monitoring and control"
    end
  end
end
