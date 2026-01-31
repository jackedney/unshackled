defmodule UnshackledWeb.SessionsLive.IndexTest do
  use UnshackledWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo

  setup do
    # Clear all blackboard records before each test
    Repo.delete_all(BlackboardRecord)
    :ok
  end

  describe "Sessions list page" do
    test "renders empty state when no sessions exist", %{conn: conn} do
      {:ok, view, html} = live(conn, "/sessions")

      assert html =~ "Sessions"
      assert html =~ "No sessions found"
      assert html =~ "Start a new session to begin reasoning"
      assert has_element?(view, "a[href='/sessions/new']")
    end

    test "renders sessions cards when sessions exist", %{conn: conn} do
      # Create a test blackboard record
      {:ok, _blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Test claim for reasoning",
          support_strength: 0.65,
          cycle_count: 10
        })
        |> Repo.insert()

      {:ok, view, html} = live(conn, "/sessions")

      assert html =~ "Sessions"
      refute html =~ "No sessions found"
      assert html =~ "Test claim for reasoning"
      assert html =~ "10"
      assert html =~ "65.0%"
      assert has_element?(view, ".session-card")
    end

    test "truncates long claims in cards", %{conn: conn} do
      long_claim = String.duplicate("This is a test claim. ", 20)

      {:ok, _blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: long_claim,
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, "/sessions")

      # Should have line-clamp-2 class for truncation
      assert html =~ "line-clamp-2"
      # Should contain full claim in HTML (CSS truncates display, not content)
      assert html =~ long_claim
    end

    test "displays correct status for graduated session", %{conn: conn} do
      {:ok, _blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Graduated claim",
          support_strength: 0.85,
          cycle_count: 50
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, "/sessions")

      assert html =~ "Graduated"
    end

    test "displays correct status for dead session", %{conn: conn} do
      {:ok, _blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Dead claim",
          support_strength: 0.2,
          cycle_count: 30
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, "/sessions")

      assert html =~ "Dead"
    end

    test "clicking card navigates to session detail page", %{conn: conn} do
      {:ok, blackboard} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Clickable claim",
          support_strength: 0.6,
          cycle_count: 15
        })
        |> Repo.insert()

      {:ok, view, _html} = live(conn, "/sessions")

      # The card is a link that navigates to session detail
      assert has_element?(view, "a[href='/sessions/#{blackboard.id}']")
    end

    test "displays New Session button in header", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions")

      assert has_element?(view, "a[href='/sessions/new']")
      assert has_element?(view, "button", "New Session")
    end

    test "displays sessions ordered by most recent first", %{conn: conn} do
      # Create first session (older - will have lower ID)
      {:ok, _older} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Older claim",
          support_strength: 0.5,
          cycle_count: 5
        })
        |> Repo.insert()

      # Create second session (newer - will have higher ID)
      {:ok, _newer} =
        %BlackboardRecord{}
        |> BlackboardRecord.changeset(%{
          current_claim: "Newer claim",
          support_strength: 0.6,
          cycle_count: 10
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, "/sessions")

      # Newer (higher ID) should appear before older (lower ID) in the HTML
      newer_pos = :binary.match(html, "Newer claim") |> elem(0)
      older_pos = :binary.match(html, "Older claim") |> elem(0)

      assert newer_pos < older_pos
    end
  end
end
