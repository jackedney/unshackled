defmodule Unshackled.Agents.Quantifier do
  @moduledoc """
  Quantifier agent that adds numerical precision to claims.

  The Quantifier agent takes the current claim and adds specific numerical
  bounds or parameters to make it more precise. The agent must acknowledge
  whether the bounds are arbitrary or principled.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server

  @arbitrary_without_acknowledgment_indicators [
    "i think",
    "maybe",
    "approximately",
    "roughly",
    "about",
    "around",
    "somehow",
    "some value"
  ]

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :quantifier
  def role, do: :quantifier

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to add numerical bounds or parameters
  to the claim and explicitly acknowledge whether they are arbitrary
  or principled.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{current_claim: claim}) do
    """
    You are adding numerical precision to the following claim.

    Current claim: #{claim}

    Your task:
    1. Identify places in the claim that can be made more precise with numerical bounds.
    2. Add specific numerical values, ranges, or parameters.
    3. Provide a principled justification for why those specific numbers were chosen.
    4. EXPLICITLY STATE whether your bounds are ARBITRARY or PRINCIPLED.
       - PRINCIPLED: Based on theory, empirical evidence, or known physical/mathematical constants
       - ARBITRARY: Chosen as a working hypothesis without strong theoretical justification

    CRITICAL: You must acknowledge whether bounds are arbitrary or principled
    - Invalid: "The scale is around 10^-9 meters" (arbitrary bounds without acknowledgment)
    - Valid: "The scale is approximately 10^-9 meters (ARBITRARY: chosen as a working hypothesis)"
    - Valid: "The scale is 10^-35 meters based on Planck length (PRINCIPLED: derived from fundamental constants)"

    Required response format (JSON):
    {
      "quantified_claim": "The claim with numerical bounds added",
      "bounds": "Description of the numerical bounds or parameters added",
      "bounds_justification": "Detailed explanation of why these specific values were chosen",
      "arbitrary_flag": true/false
    }

    Examples:

    Example 1 - Planck scale principled bounds:
    {
      "quantified_claim": "Thermodynamics is local at scales below 10^-35 meters (the Planck length)",
      "bounds": "Scale threshold at 10^-35 meters",
      "bounds_justification": "The Planck length (ℓP = √(ħG/c³) ≈ 1.6×10^-35 m) represents the scale at which quantum gravitational effects become significant. Below this scale, our current physical theories break down, suggesting spacetime itself may not be continuous.",
      "arbitrary_flag": false
    }

    Example 2 - Working hypothesis arbitrary bounds:
    {
      "quantified_claim": "The system exhibits coherent behavior for durations up to 10^-12 seconds (ARBITRARY: working hypothesis)",
      "bounds": "Temporal coherence window of 10^-12 seconds",
      "bounds_justification": "This duration is proposed as a working hypothesis based on typical decoherence times in quantum systems, but lacks direct experimental validation. The value should be tested and refined through empirical measurement.",
      "arbitrary_flag": true
    }

    Example 3 - Empirical principled bounds:
    {
      "quantified_claim": "Entropy production exceeds 10^-23 J/K per cycle in the nanoscale system",
      "bounds": "Minimum entropy production of 10^-23 J/K per cycle",
      "bounds_justification": "Based on experimental measurements of similar nanoscale thermal systems reported in Nature Physics 2022, which show consistent lower bounds on entropy production even in reversible regimes.",
      "arbitrary_flag": false
    }

    Invalid response (arbitrary bounds without acknowledgment):
    {
      "quantified_claim": "The system operates efficiently up to maybe 10^8 operations",
      "bounds": "Up to 10^8 operations",
      "bounds_justification": "This seems like a reasonable limit",
      "arbitrary_flag": false
    }

    Invalid response (arbitrary bounds but claims principled without justification):
    {
      "quantified_claim": "The effect occurs at scales around 10^-6 meters",
      "bounds": "Scale of 10^-6 meters",
      "bounds_justification": "This is the right scale",
      "arbitrary_flag": false
    }

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts the quantified claim, bounds, justification, and arbitrary flag.

  Returns a map with:
  - quantified_claim: the claim with numerical bounds
  - bounds: description of numerical bounds added
  - bounds_justification: explanation for why those specific values
  - arbitrary_flag: boolean indicating if bounds are arbitrary
  - valid: boolean indicating if the response was properly formatted

  Invalid responses are flagged if:
  - Arbitrary bounds detected but not acknowledged (arbitrary_flag is false but justification is weak)
  - Missing required fields
  - Malformed JSON
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "quantified_claim" => claim,
         "bounds" => bounds,
         "bounds_justification" => justification,
         "arbitrary_flag" => arbitrary_flag
       } = data} ->
        build_response_map(claim, bounds, justification, arbitrary_flag, data)

      {:ok, _partial} ->
        error_response(
          "Missing required fields: quantified_claim, bounds, bounds_justification, and arbitrary_flag"
        )

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(term(), term(), term(), term(), map()) :: map()
  defp build_response_map(claim, bounds, justification, arbitrary_flag, _data) do
    base = %{
      quantified_claim: claim,
      bounds: bounds,
      bounds_justification: justification,
      arbitrary_flag: arbitrary_flag
    }

    cond do
      not is_binary(claim) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "quantified_claim must be a string")

      not is_binary(justification) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "bounds_justification must be a string")

      not is_boolean(arbitrary_flag) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "arbitrary_flag must be a boolean value")

      arbitrary_without_acknowledgment?(claim, justification, arbitrary_flag) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Arbitrary bounds detected without proper acknowledgment in quantified_claim or justification"
        )

      not contains_numerical_value?(claim) and not contains_numerical_value?(bounds) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "No numerical bounds or values detected - must add specific numbers")

      String.length(String.trim(claim)) < 15 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Quantified claim is too short - must include numerical precision")

      String.length(String.trim(justification)) < 30 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Bounds justification is too short - must explain why these specific values were chosen"
        )

      true ->
        Map.put(base, :valid, true)
    end
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      quantified_claim: nil,
      bounds: nil,
      bounds_justification: nil,
      arbitrary_flag: nil,
      valid: false,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Quantifier agent.

  The Quantifier suggests +0.05 confidence boost when it adds
  numerical precision to a claim.
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(%{valid: true}), do: 0.05

  def confidence_delta(%{valid: false}), do: 0.0

  @spec arbitrary_without_acknowledgment?(String.t(), String.t(), boolean()) :: boolean()
  defp arbitrary_without_acknowledgment?(claim, justification, arbitrary_flag)
       when is_binary(claim) and is_binary(justification) do
    if arbitrary_flag == false do
      lower_claim = String.downcase(claim)
      lower_justification = String.downcase(justification)

      has_arbitrary_language? =
        Enum.any?(@arbitrary_without_acknowledgment_indicators, fn indicator ->
          String.contains?(lower_claim, indicator) or
            String.contains?(lower_justification, indicator)
        end)

      lacks_acknowledgment? =
        not String.contains?(lower_claim, "arbitrary") and
          not String.contains?(lower_claim, "working hypothesis") and
          not String.contains?(lower_justification, "arbitrary") and
          not String.contains?(lower_justification, "working hypothesis")

      has_arbitrary_language? and lacks_acknowledgment?
    else
      false
    end
  end

  defp arbitrary_without_acknowledgment?(_, _, _), do: false

  @spec contains_numerical_value?(String.t()) :: boolean()
  defp contains_numerical_value?(text) when is_binary(text) do
    Regex.match?(~r/\d+(\.\d+)?|\d+[eE][+-]?\d+/, text)
  end

  defp contains_numerical_value?(_), do: false
end
