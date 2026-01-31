defmodule Unshackled.Evolution.ClaimDiffTest do
  use ExUnit.Case, async: false
  doctest Unshackled.Evolution.ClaimDiff

  alias Unshackled.Evolution.ClaimDiff
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

  describe "generate_diff/2" do
    test "returns empty diff for identical claims" do
      claim = "AI will transform business"

      assert {:ok, diff} = ClaimDiff.generate_diff(claim, claim)

      assert diff.additions == []
      assert diff.removals == []
      assert diff.modifications == []
    end

    test "returns empty diff for claims with only whitespace differences" do
      previous = "AI will transform business"
      new = "  AI will transform business  "

      assert {:ok, diff} = ClaimDiff.generate_diff(previous, new)

      assert diff.additions == []
      assert diff.removals == []
      assert diff.modifications == []
    end

    test "identifies additions, removals, and modifications for different claims" do
      previous = "AI will transform business"
      new = "Companies not adopting AI will lose competitive advantage"

      mock_diff_response = ~s({
        "additions": ["competitive advantage", "companies", "non-adoption consequence"],
        "removals": ["general transformation"],
        "modifications": ["AI focus"]
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      assert {:ok, diff} = ClaimDiff.generate_diff(previous, new)

      assert length(diff.additions) > 0
      assert length(diff.removals) > 0
      assert length(diff.modifications) > 0
    end

    test "returns error for invalid input types" do
      assert {:error, :invalid_input} = ClaimDiff.generate_diff(nil, "claim")
      assert {:error, :invalid_input} = ClaimDiff.generate_diff("claim", nil)
      assert {:error, :invalid_input} = ClaimDiff.generate_diff(123, "claim")
    end

    test "handles empty strings" do
      previous = ""
      new = "New claim"

      mock_diff_response = ~s({
        "additions": ["New claim"],
        "removals": [],
        "modifications": []
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      assert {:ok, diff} = ClaimDiff.generate_diff(previous, new)

      assert is_list(diff.additions)
    end

    test "normalizes diff lists to remove empty strings" do
      previous = "AI helps"
      new = "AI hurts"

      mock_diff_response = ~s({
        "additions": ["hurts"],
        "removals": ["helps", ""],
        "modifications": [""]
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      assert {:ok, diff} = ClaimDiff.generate_diff(previous, new)

      refute Enum.any?(diff.additions, &(&1 == ""))
      refute Enum.any?(diff.removals, &(&1 == ""))
      refute Enum.any?(diff.modifications, &(&1 == ""))
    end

    test "handles very long claims" do
      previous = String.duplicate("This is a very long claim. ", 20)
      new = String.duplicate("This is another very long claim. ", 20)

      mock_diff_response = ~s({
        "additions": ["another"],
        "removals": ["very"],
        "modifications": []
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      assert {:ok, diff} = ClaimDiff.generate_diff(previous, new)

      assert is_list(diff.additions)
      assert is_list(diff.removals)
      assert is_list(diff.modifications)
    end
  end

  describe "highlight_changes/2" do
    test "returns HTML-safe markup for both claims" do
      previous = "AI will transform business"
      new = "AI technology is beneficial"

      mock_diff_response = ~s({
        "additions": ["technology", "beneficial"],
        "removals": ["will transform", "business"],
        "modifications": []
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      assert {:ok, html} = ClaimDiff.highlight_changes(previous, new)

      assert is_binary(html.previous_claim_html)
      assert is_binary(html.new_claim_html)
      assert String.contains?(html.previous_claim_html, "&lt;span")
      assert String.contains?(html.new_claim_html, "&lt;span")
    end

    test "includes diff markup when concepts changed" do
      previous = "AI is good"
      new = "AI technology is beneficial"

      mock_diff_response = ~s({
        "additions": ["technology", "beneficial"],
        "removals": ["good"],
        "modifications": []
      })

      Unshackled.LLM.MockClient
      |> expect(:chat, fn "anthropic/claude-haiku-4.5", _messages ->
        {:ok, %{content: mock_diff_response}}
      end)

      assert {:ok, html} = ClaimDiff.highlight_changes(previous, new)

      assert is_binary(html.previous_claim_html)
      assert is_binary(html.new_claim_html)
      assert String.contains?(html.previous_claim_html, "diff-remove")
      assert String.contains?(html.new_claim_html, "diff-add")
    end

    test "handles empty diff result" do
      previous = "Same claim"
      new = "Same claim"

      assert {:ok, html} = ClaimDiff.highlight_changes(previous, new)

      assert html.previous_claim_html == "Same claim"
      assert html.new_claim_html == "Same claim"
    end

    test "uses provided diff result" do
      previous = "Test claim"
      new = "Another test"

      diff = %{
        additions: ["new concept"],
        removals: ["old concept"],
        modifications: ["changed"]
      }

      assert {:ok, html} = ClaimDiff.highlight_changes(previous, new, diff)

      assert is_binary(html.previous_claim_html)
      assert is_binary(html.new_claim_html)
    end

    test "handles invalid input" do
      assert {:error, :invalid_input} = ClaimDiff.highlight_changes(nil, "claim")
      assert {:error, :invalid_input} = ClaimDiff.highlight_changes("claim", nil)
    end
  end

  describe "highlight_changes/3 with pre-generated diff" do
    test "uses provided diff instead of regenerating" do
      previous = "AI will transform"
      new = "AI transforms companies"

      custom_diff = %{
        additions: ["companies"],
        removals: ["will"],
        modifications: ["transform"]
      }

      assert {:ok, html} = ClaimDiff.highlight_changes(previous, new, custom_diff)

      assert is_binary(html.previous_claim_html)
      assert is_binary(html.new_claim_html)
    end

    test "handles empty diff lists" do
      previous = "Test claim"
      new = "Test claim"

      empty_diff = %{
        additions: [],
        removals: [],
        modifications: []
      }

      assert {:ok, html} = ClaimDiff.highlight_changes(previous, new, empty_diff)

      assert is_binary(html.previous_claim_html)
      assert is_binary(html.new_claim_html)
    end
  end
end
