defmodule Unshackled.Agents.BoundaryHunter do
  @moduledoc """
  Boundary Hunter agent that finds edge cases where claims break.

  The Boundary Hunter agent identifies specific edge cases or boundary
  conditions where a claim would fail, break down, or produce contradictory
  results. It focuses on concrete, testable scenarios rather than general
  skepticism.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server

  @general_skepticism_phrases [
    "we can never be sure",
    "cannot be proven",
    "impossible to verify",
    "always uncertain",
    "fundamentally unknowable",
    "beyond testing",
    "cannot confirm",
    "might be wrong",
    "could be false",
    "no way to know",
    "we cannot determine",
    "cannot establish",
    "impossible to establish",
    "cannot be certain"
  ]

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :boundary_hunter
  def role, do: :boundary_hunter

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to find a specific edge case or boundary
  condition where the claim breaks, enforcing concrete testable scenarios
  rather than general skepticism.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{current_claim: claim}) do
    """
    You are finding an edge case where the following claim breaks.

    Current claim: #{claim}

    Your task:
    1. Identify a specific edge case, boundary condition, or extreme scenario
    2. Explain exactly how and why the claim breaks in this case
    3. Describe the consequence or paradox that results

    CRITICAL: Find SPECIFIC edge cases, not general skepticism
    - SPECIFIC EDGE CASE: A concrete scenario with testable conditions
    - GENERAL SKEPTICISM: "We can never be sure" or other hand-waving doubts

    FORBIDDEN patterns (any use invalidates your response):
    - "We can never be sure" or similar epistemological doubts
    - "Cannot be proven" or "impossible to verify"
    - General uncertainty without specific conditions
    - "This might be wrong" without identifying the specific case

    Required response format (JSON):
    {
      "edge_case": "A specific, testable edge case or boundary condition",
      "why_it_breaks": "Explanation of how the claim fails in this case",
      "consequence": "The paradox, contradiction, or failure that results"
    }

    Example:
    If given: "Local thermodynamics allows entropy to decrease in isolated quantum systems"
    Valid response:
    {
      "edge_case": "At the event horizon of a black hole, where quantum effects and extreme gravity interact",
      "why_it_breaks": "The event horizon creates a region where information is paradoxically both preserved and destroyed, contradicting the assumption that isolated systems can maintain coherence long enough for entropy reversal",
      "consequence": "This produces the black hole information paradox, suggesting that local thermodynamics breaks down at the boundary of extreme gravitational fields"
    }

    Another example:
    If given: "All observers measure the same speed of light in vacuum"
    Valid response:
    {
      "edge_case": "When an observer is within the Schwarzschild radius of a black hole",
      "why_it_breaks": "Light cannot escape from within the event horizon, meaning the concept of 'measuring the speed of light' becomes operationally undefined for such observers",
      "consequence": "The claim's applicability is limited to regions where causal structure allows light propagation, breaking down at black hole boundaries"
    }

    Invalid response (general skepticism):
    {
      "edge_case": "We can never be sure quantum effects are real",
      "why_it_breaks": "...",
      "consequence": "..."
    }
    Error: This is general skepticism, not a specific edge case

    Invalid response (impossible to verify):
    {
      "edge_case": "Conditions that cannot be tested or observed",
      "why_it_breaks": "Since we cannot verify, the claim might be false",
      "consequence": "..."
    }
    Error: This is epistemological doubt, not a concrete boundary condition

    Valid edge case examples:
    - "At absolute zero temperature" → Physical boundary where quantum effects dominate
    - "At the Planck scale (~10^-35 m)" → Scale where current physics breaks down
    - "When system size approaches atomic dimensions" → Boundary where classical assumptions fail
    - "Under infinite acceleration" → Extremal condition producing contradictions
    - "At the event horizon of a black hole" → Gravitational boundary with paradoxes
    - "When observing time intervals shorter than Planck time" → Temporal boundary

    Invalid edge case examples (general skepticism):
    - "In conditions we cannot observe" → Epistemological limitation, not physical boundary
    - "In scenarios beyond our understanding" → General ignorance, not specific condition
    - "Where our theories might be wrong" → Possibility of error, not concrete case
    - "In fundamentally unknowable situations" → Philosophical skepticism, not testable scenario

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts the edge case, why it breaks, and consequence.

  Returns a map with:
  - edge_case: the specific edge case or boundary condition
  - why_it_breaks: explanation of how the claim fails
  - consequence: the resulting paradox or contradiction
  - valid: boolean indicating if the response was properly formatted

  Invalid responses are flagged if:
  - Contains general skepticism phrases
  - Missing required fields
  - Malformed JSON
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "edge_case" => edge_case,
         "why_it_breaks" => why_breaks,
         "consequence" => consequence
       } = data} ->
        build_response_map(edge_case, why_breaks, consequence, data)

      {:ok, _partial} ->
        error_response("Missing required fields: edge_case, why_it_breaks, and consequence")

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(String.t(), String.t(), String.t(), map()) :: map()
  defp build_response_map(edge_case, why_breaks, consequence, _data) do
    base = %{
      edge_case: edge_case,
      why_it_breaks: why_breaks,
      consequence: consequence
    }

    cond do
      contains_general_skepticism?(edge_case) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Edge case contains general skepticism instead of specific boundary condition"
        )

      contains_general_skepticism?(why_breaks) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Explanation contains general skepticism instead of specific mechanism"
        )

      contains_general_skepticism?(consequence) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Consequence contains general skepticism instead of specific result")

      not is_binary(edge_case) or String.length(String.trim(edge_case)) < 15 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "edge_case must be a non-empty string describing a specific condition")

      not is_binary(why_breaks) or String.length(String.trim(why_breaks)) < 15 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "why_it_breaks must be a non-empty string explaining the failure")

      not is_binary(consequence) or String.length(String.trim(consequence)) < 15 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "consequence must be a non-empty string describing the result")

      true ->
        Map.put(base, :valid, true)
    end
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      edge_case: nil,
      why_it_breaks: nil,
      consequence: nil,
      valid: false,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Boundary Hunter agent.

  The Boundary Hunter suggests -0.10 confidence penalty when it
  finds a valid breaking case.
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(%{valid: true}), do: -0.10

  def confidence_delta(%{valid: false}), do: 0.0

  @spec contains_general_skepticism?(String.t()) :: boolean()
  defp contains_general_skepticism?(text) when is_binary(text) do
    lower_text = String.downcase(text)

    Enum.any?(@general_skepticism_phrases, fn phrase ->
      String.contains?(lower_text, phrase)
    end)
  end

  defp contains_general_skepticism?(_), do: false
end
