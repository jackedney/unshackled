defmodule Unshackled.Evolution.ClaimDiff do
  @moduledoc """
  Module for generating semantic diffs between claim versions.

  This module uses an LLM to identify meaningful semantic changes between
  two claim versions, focusing on concepts rather than character-level diffs.
  """

  alias Unshackled.LLM.Client
  alias Unshackled.Evolution.Config

  @type diff_result :: %{
          additions: [String.t()],
          removals: [String.t()],
          modifications: [String.t()]
        }

  @type html_result :: %{
          previous_claim_html: String.t(),
          new_claim_html: String.t()
        }

  @doc """
  Generates a semantic diff between two claim versions.

  Uses an LLM to identify concepts that were added, removed, or modified.
  Returns structured data with lists of concepts for each change type.

  ## Parameters

  - previous_claim: The original claim text
  - new_claim: The modified claim text

  ## Returns

  A map with keys:
  - additions: list of concepts added to the new claim
  - removals: list of concepts removed from the previous claim
  - modifications: list of concepts that were refined/changed

  ## Examples

      iex> Unshackled.Evolution.ClaimDiff.generate_diff("Same claim", "Same claim")
      {:ok, %{additions: [], removals: [], modifications: []}}

  """
  @spec generate_diff(String.t(), String.t()) :: {:ok, diff_result()} | {:error, term()}
  def generate_diff(previous_claim, new_claim)
      when is_binary(previous_claim) and is_binary(new_claim) do
    if String.trim(previous_claim) == String.trim(new_claim) do
      {:ok, %{additions: [], removals: [], modifications: []}}
    else
      call_diff_llm(previous_claim, new_claim)
    end
  end

  def generate_diff(_previous_claim, _new_claim) do
    {:error, :invalid_input}
  end

  @doc """
  Generates HTML-safe markup with highlighting for UI display.

  Wraps added concepts in <span class="diff-add"> tags (green),
  removed concepts in <span class="diff-remove"> tags (red with strikethrough),
  and modified concepts in <span class="diff-modify"> tags (yellow).

  ## Parameters

  - previous_claim: The original claim text
  - new_claim: The modified claim text
  - diff_result: The diff result from generate_diff/2 (optional, will generate if not provided)

  ## Returns

  A map with HTML-safe versions of both claims.

  ## Examples

      iex> {:ok, html} = Unshackled.Evolution.ClaimDiff.highlight_changes("Same claim", "Same claim")
      iex> is_binary(html.previous_claim_html)
      true

  """
  @spec highlight_changes(String.t(), String.t(), diff_result() | nil) ::
          {:ok, html_result()} | {:error, term()}
  def highlight_changes(previous_claim, new_claim, diff_result \\ nil) do
    with {:ok, diff} <-
           if(diff_result, do: {:ok, diff_result}, else: generate_diff(previous_claim, new_claim)) do
      previous_html =
        apply_diff_markup(previous_claim, diff.additions ++ diff.modifications, [], diff.removals)

      new_html = apply_diff_markup(new_claim, diff.additions, diff.modifications, diff.removals)

      {:ok, %{previous_claim_html: previous_html, new_claim_html: new_html}}
    end
  end

  defp call_diff_llm(previous_claim, new_claim) do
    model = Config.summarizer_model()

    messages = [
      %{
        role: "system",
        content:
          "You are a semantic diff analyzer specialized in identifying meaningful concept-level changes between text versions. Focus on substantive changes in meaning, not just word-level edits."
      },
      %{
        role: "user",
        content: """
        Compare these two claim versions and identify semantic changes:

        Previous claim: #{previous_claim}

        New claim: #{new_claim}

        Your task:
        1. Identify concepts ADDED in the new claim (new ideas, entities, or perspectives not present before)
        2. Identify concepts REMOVED from the previous claim (ideas or perspectives no longer present)
        3. Identify concepts MODIFIED (ideas that were present but were refined, expanded, or changed in meaning)

        Return ONLY valid JSON in this format:
        {
          "additions": ["concept 1", "concept 2"],
          "removals": ["concept 1"],
          "modifications": ["refined concept"]
        }

        Rules:
        - Be specific: "companies" not "general expansion"
        - Focus on meaning, not just word changes
        - If the claims are essentially the same with minor wording differences, return empty arrays
        - Keep items short (2-5 words)
        - Maximum 5 items per category

        Examples:
        "AI will transform business" -> "Companies not adopting AI will lose competitive advantage"
        Result: {"additions": ["competitive advantage", "companies", "non-adoption consequence"], "removals": ["general transformation"], "modifications": ["AI focus"]}
        """
      }
    ]

    case Client.chat(model, messages) do
      {:ok, response_struct} ->
        parse_diff_response(response_struct.content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_diff_response(response) do
    case Jason.decode(response) do
      {:ok, %{"additions" => additions, "removals" => removals, "modifications" => modifications}}
      when is_list(additions) and is_list(removals) and is_list(modifications) ->
        {:ok,
         %{
           additions: normalize_list(additions),
           removals: normalize_list(removals),
           modifications: normalize_list(modifications)
         }}

      _ ->
        {:error, :invalid_response_format}
    end
  end

  defp normalize_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp apply_diff_markup(text, add_concepts, mod_concepts, rem_concepts) do
    text
    |> wrap_concepts(rem_concepts, "diff-remove")
    |> wrap_concepts(mod_concepts, "diff-modify")
    |> wrap_concepts(add_concepts, "diff-add")
    |> html_escape()
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp wrap_concepts(text, [], _class), do: text

  defp wrap_concepts(text, concepts, class) when is_list(concepts) do
    Enum.reduce(concepts, text, fn concept, acc ->
      if String.length(concept) > 0 do
        regex = ~r/(#{Regex.escape(concept)})/i
        String.replace(acc, regex, "<span class=\"#{class}\">\\1</span>")
      else
        acc
      end
    end)
  end
end
