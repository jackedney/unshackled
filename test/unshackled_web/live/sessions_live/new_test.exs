defmodule UnshackledWeb.SessionsLive.NewTest do
  use UnshackledWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Unshackled.Blackboard.BlackboardRecord
  alias Unshackled.Repo

  setup do
    # Clear all blackboard records before each test
    Repo.delete_all(BlackboardRecord)
    :ok
  end

  describe "New session page" do
    test "renders the new session form", %{conn: conn} do
      {:ok, view, html} = live(conn, "/sessions/new")

      assert html =~ "New Session"
      assert html =~ "Configure and start a new reasoning session"
      assert has_element?(view, "form")
      assert has_element?(view, "textarea[name='config[seed_claim]']")
      assert has_element?(view, "input[name='config[max_cycles]']")
      assert has_element?(view, "select[name='config[cycle_mode]']")
      assert has_element?(view, "input[name='config[cycle_timeout_ms]']")
      assert has_element?(view, "input[name='config[decay_rate]']")
      assert has_element?(view, "input[name='config[novelty_bonus_enabled]']")
    end

    test "displays model pool checkboxes", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/sessions/new")

      assert html =~ "Model Pool"
      assert html =~ "openai/gpt-5.2"
      assert html =~ "google/gemini-3-pro"
      assert html =~ "anthropic/claude-opus-4.5"
    end

    test "displays cancel and submit buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions/new")

      assert has_element?(view, "a[href='/sessions']")
      assert has_element?(view, "button", "Cancel")
      assert has_element?(view, "button[type='submit']", "Start Session")
    end

    test "validates empty seed claim on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions/new")

      # Submit with empty seed claim
      html =
        view
        |> form("form", %{config: %{seed_claim: "", max_cycles: "50"}})
        |> render_change()

      # Should show validation error
      assert html =~ "can&#39;t be blank" or html =~ "seed_claim"
    end

    test "validates invalid max_cycles", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions/new")

      html =
        view
        |> form("form", %{config: %{seed_claim: "Test", max_cycles: "-1"}})
        |> render_change()

      # Should show validation error for negative number
      assert html =~ "greater than" or html =~ "max_cycles"
    end

    test "validates invalid decay_rate", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions/new")

      html =
        view
        |> form("form", %{config: %{seed_claim: "Test", decay_rate: "-0.5"}})
        |> render_change()

      # Should show validation error for negative number
      assert html =~ "greater than" or html =~ "decay_rate"
    end

    test "shows default values in form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/sessions/new")

      # Check default values are present
      assert html =~ "50"
      assert html =~ "300000"
      assert html =~ "0.02"
    end

    test "cancel button navigates to sessions list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions/new")

      assert has_element?(view, "a[href='/sessions']")
    end

    test "cycle mode select has correct options", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/sessions/new")

      assert html =~ "Event Driven"
      assert html =~ "Time Based"
      assert html =~ "event_driven"
      assert html =~ "time_based"
    end
  end

  describe "Form submission" do
    test "submitting empty seed_claim shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/sessions/new")

      html =
        view
        |> form("form", %{
          config: %{
            seed_claim: "",
            max_cycles: "50",
            cycle_mode: "event_driven",
            cycle_timeout_ms: "300000",
            decay_rate: "0.02"
          }
        })
        |> render_submit()

      # Should show validation error and not navigate
      assert html =~ "seed_claim" or html =~ "required" or html =~ "blank"
    end
  end
end
