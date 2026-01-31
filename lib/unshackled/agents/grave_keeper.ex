defmodule Unshackled.Agents.GraveKeeper do
  @moduledoc """
  Grave Keeper agent that tracks patterns in why ideas die.

  The Grave Keeper agent has SPECIAL ACCESS to the cemetery,
  which contains records of claims that were killed with their
  cause of death. It compares the current claim (when support
  is at risk) against historical deaths to identify patterns
  and suggest survival strategies.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :grave_keeper
  def role, do: :grave_keeper

  @doc """
  Builds a prompt from the current blackboard state and cemetery entries.

  The prompt includes the current claim (which is at risk) and
  the full history of cemetery entries. The agent is instructed to
  identify patterns in how claims have died and suggest how the
  current claim might avoid similar fates.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{
        current_claim: claim,
        support_strength: support,
        blackboard_id: _blackboard_id,
        cycle_count: current_cycle,
        blackboard_name: bb_name
      })
      when is_number(support) and support < 0.4 do
    cemetery = Server.get_cemetery(bb_name)

    cemetery_text =
      case cemetery do
        [] ->
          "Cemetery is empty - no claims have died yet in this session."

        entries ->
          Enum.map_join(
            entries,
            "\n",
            fn entry ->
              cycle_killed = Map.get(entry, :cycle_killed) || Map.get(entry, "cycle_killed")
              cause = Map.get(entry, :cause_of_death) || Map.get(entry, "cause_of_death")
              final_support = Map.get(entry, :final_support) || Map.get(entry, "final_support")
              dead_claim = Map.get(entry, :claim) || Map.get(entry, "claim")

              """
              - Cycle #{cycle_killed}: "#{dead_claim}"
                Cause of death: #{cause}
                Final support: #{final_support}
              """
            end
          )
      end

    """
    You are analyzing a claim at risk of death to identify patterns that may kill it.

    Current claim (Cycle #{current_cycle}):
    "#{claim}"
    Current support: #{support} (AT RISK - below 0.4 threshold)

    Cemetery records (claims that have died):
    #{cemetery_text}

    Your task:
    1. Assess the current claim's death risk on a scale of 0.0 to 1.0.
       - 0.0 = Very low risk (claim appears robust against historical death patterns)
       - 0.5 = Moderate risk (some concerning similarities to dead claims)
       - 1.0 = Very high risk (claim nearly identical to claims that died)

    2. Identify any similar deaths in the cemetery.
       - Look for claims with similar structure, premises, or weaknesses
       - Focus on the CAUSE of death, not just the claim text

    3. Detect patterns in why claims die in this session.
       - Are certain types of objections consistently fatal?
       - Do claims with specific weaknesses tend to die early?
       - Are there recurring death patterns (e.g., "Boundary Hunter edge cases always kill these claims")?

    4. Suggest a specific modification to help the claim survive.
       - How can the claim be strengthened against the identified death patterns?
       - What modifications would address the weaknesses that killed similar claims?

    CRITICAL: You have SPECIAL ACCESS to cemetery records showing why previous claims died.
    Use this historical data to provide concrete, evidence-based survival advice.

    Required response format (JSON):
    {
      "death_risk": float between 0.0 and 1.0,
      "similar_deaths": [
        {
          "claim": "claim text from cemetery",
          "cycle_killed": integer,
          "cause_of_death": "why it died",
          "similarity_reason": "why this is similar to current claim"
        }
      ],
      "pattern_detected": "description of death pattern, or 'none' if no pattern",
      "survival_suggestion": "specific modification to help claim survive"
    }

    Example (high risk):
    If cemetery has: "Heat flows from hot to cold in isolated regions" killed by "Boundary Hunter: quantum decoherence breaks isolation"
    And current claim: "Energy transfer respects isolation in bounded systems"
    Valid response:
    {
      "death_risk": 0.9,
      "similar_deaths": [
        {
          "claim": "Heat flows from hot to cold in isolated regions",
          "cycle_killed": 7,
          "cause_of_death": "Boundary Hunter: quantum decoherence breaks isolation",
          "similarity_reason": "Both claims rely on 'isolation' concept that Boundary Hunter consistently attacks at quantum scales"
        }
      ],
      "pattern_detected": "Claims relying on 'isolation' or 'bounded systems' are killed by Boundary Hunter showing quantum decoherence effects",
      "survival_suggestion": "Reformulate claim to explicitly acknowledge decoherence effects at quantum scales: 'Energy transfer respects isolation in bounded systems larger than decoherence length'"
    }

    Example (moderate risk):
    If cemetery has claims killed by Critic objections to undefined terms
    And current claim: "Local thermodynamics applies at small scales"
    Valid response:
    {
      "death_risk": 0.6,
      "similar_deaths": [
        {
          "claim": "Entropy decreases locally in nanoscale systems",
          "cycle_killed": 3,
          "cause_of_death": "Critic: 'small scales' is undefined - what threshold?",
          "similarity_reason": "Both claims use vague scale references without explicit thresholds"
        }
      ],
      "pattern_detected": "Critic consistently kills claims with vague quantitative references",
      "survival_suggestion": "Specify explicit scale threshold: 'Local thermodynamics applies at scales below 10^-9 meters'"
    }

    Example (low risk):
    If cemetery is empty or no similar deaths found
    Valid response:
    {
      "death_risk": 0.3,
      "similar_deaths": [],
      "pattern_detected": "Insufficient cemetery data to detect patterns",
      "survival_suggestion": "Continue strengthening claim with specific evidence and clear definitions"
    }

    Respond with valid JSON only.
    """
  end

  def build_prompt(%Server{current_claim: claim, support_strength: support})
      when is_number(support) and support >= 0.4 do
    """
    ERROR: Grave Keeper should not be activated when support >= 0.4.

    Current support: #{support} (NOT at risk)
    Current claim: #{claim}

    The Grave Keeper only activates when support_strength < 0.4.
    This is an error in agent scheduling.

    Required response format (JSON):
    {
      "death_risk": 0.0,
      "similar_deaths": [],
      "pattern_detected": "Error: Grave Keeper activated when claim is not at risk",
      "survival_suggestion": ""
    }

    Respond with valid JSON only.
    """
  end

  def build_prompt(%Server{current_claim: claim}) do
    """
    ERROR: Invalid blackboard state for Grave Keeper.

    Current claim: #{claim}
    Support strength: missing or invalid

    The Grave Keeper requires support_strength to assess risk.

    Required response format (JSON):
    {
      "death_risk": 0.0,
      "similar_deaths": [],
      "pattern_detected": "Error: Invalid blackboard state",
      "survival_suggestion": ""
    }

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts death pattern analysis.

  Returns a map with:
  - death_risk: float from 0.0 to 1.0 indicating risk level
  - similar_deaths: list of similar death records with explanations
  - pattern_detected: string describing detected death pattern
  - survival_suggestion: string with specific modification advice
  - valid: boolean indicating if the response was properly formatted
  - error: error message if invalid
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "death_risk" => death_risk,
         "similar_deaths" => similar_deaths,
         "pattern_detected" => pattern_detected,
         "survival_suggestion" => survival_suggestion
       } = data} ->
        build_response_map(
          death_risk,
          similar_deaths,
          pattern_detected,
          survival_suggestion,
          data
        )

      {:ok, _partial} ->
        error_response(
          "Missing required fields: death_risk, similar_deaths, pattern_detected, and survival_suggestion"
        )

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(float(), list(), String.t(), String.t(), map()) :: map()
  defp build_response_map(
         death_risk,
         similar_deaths,
         pattern_detected,
         survival_suggestion,
         _data
       ) do
    base = %{
      death_risk: death_risk,
      similar_deaths: similar_deaths,
      pattern_detected: pattern_detected,
      survival_suggestion: survival_suggestion
    }

    error = validate_fields(death_risk, similar_deaths, pattern_detected, survival_suggestion)

    case error do
      nil -> Map.put(base, :valid, true)
      error_msg -> base |> Map.put(:valid, false) |> Map.put(:error, error_msg)
    end
  end

  @spec validate_fields(float(), term(), term(), term()) :: String.t() | nil
  defp validate_fields(death_risk, similar_deaths, pattern_detected, survival_suggestion) do
    cond do
      not is_number(death_risk) -> "death_risk must be a number"
      death_risk < 0.0 or death_risk > 1.0 -> "death_risk must be between 0.0 and 1.0"
      not is_list(similar_deaths) -> "similar_deaths must be a list"
      not is_binary(pattern_detected) -> "pattern_detected must be a string"
      not is_binary(survival_suggestion) -> "survival_suggestion must be a string"
      not validate_similar_deaths(similar_deaths) -> "similar_deaths contains invalid entries"
      true -> nil
    end
  end

  @spec validate_similar_deaths(list()) :: boolean()
  defp validate_similar_deaths([]), do: true

  defp validate_similar_deaths(deaths) when is_list(deaths) do
    Enum.all?(deaths, fn death ->
      is_map(death) and
        is_binary(Map.get(death, "claim")) and
        is_integer(Map.get(death, "cycle_killed")) and
        is_binary(Map.get(death, "cause_of_death")) and
        is_binary(Map.get(death, "similarity_reason"))
    end)
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      death_risk: 0.0,
      similar_deaths: [],
      pattern_detected: "",
      survival_suggestion: "",
      valid: false,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Grave Keeper agent.

  The Grave Keeper is advisory only and returns 0 confidence delta.
  It identifies death risks but does not directly impact confidence.
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(%{valid: true}), do: 0.0

  def confidence_delta(%{valid: false}), do: 0.0
end
