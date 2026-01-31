defmodule Unshackled.Agents.Historian do
  @moduledoc """
  Historian agent that detects re-treading of previous claims.

  The Historian agent has SPECIAL ACCESS to previous claims from
  snapshots (not reasoning trajectories, just claims). It compares
  current claim against historical claims to detect repetition
  and provide novelty assessment.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :historian
  def role, do: :historian

  @doc """
  Builds a prompt from the current blackboard state and historical claims.

  The prompt includes current claim and a list of previous claims
  extracted from snapshots. The agent is instructed to identify
  re-treading patterns and assess novelty.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{
        current_claim: claim,
        blackboard_id: blackboard_id,
        cycle_count: current_cycle,
        blackboard_name: bb_name
      })
      when is_integer(blackboard_id) do
    previous_claims = fetch_previous_claims(blackboard_id, current_cycle, bb_name)

    previous_claims_text =
      case previous_claims do
        [] ->
          "No previous claims available for comparison."

        claims ->
          Enum.map_join(
            claims,
            "\n",
            fn %{cycle_number: cycle, claim: text} ->
              "  Cycle #{cycle}: #{text}"
            end
          )
      end

    """
    You are analyzing current claim for re-treading of previous positions.

    Current claim (Cycle #{current_cycle}):
    #{claim}

    Previous claims from history:
    #{previous_claims_text}

    Your task:
    1. Compare current claim against all previous claims.
    2. Identify if current claim is substantially similar to any previous claim (re-treading).
    3. List any similar claims with their cycle numbers.
    4. Assess novelty: how novel is the current direction on a scale of 0.0 to 1.0?
       - 0.0 = Complete re-treading (identical or near-identical to previous claim)
       - 0.5 = Partial overlap (some similarity but with new elements)
       - 1.0 = Completely novel direction (no meaningful similarity to history)

    CRITICAL: You ONLY have access to claim text, NOT reasoning or justification.
    Base your analysis solely on semantic similarity of claim text.

    Required response format (JSON):
    {
      "is_retread": boolean,
      "similar_claims": ["list of similar claim texts"],
      "cycle_numbers": [integers],
      "novelty_score": float between 0.0 and 1.0,
      "analysis": "Brief explanation of your assessment"
    }

    Example (re-treading):
    If current: "Heat flows from hot to cold in isolated regions"
    And cycle 12 had: "In isolated regions, heat flows from hot to cold"
    Valid response:
    {
      "is_retread": true,
      "similar_claims": ["In isolated regions, heat flows from hot to cold"],
      "cycle_numbers": [12],
      "novelty_score": 0.1,
      "analysis": "Current claim is nearly identical to cycle 12, only word order differs"
    }

    Example (novel direction):
    If current: "Quantum decoherence challenges isolation assumptions at nanoscales"
    And history has no similar concepts:
    Valid response:
    {
      "is_retread": false,
      "similar_claims": [],
      "cycle_numbers": [],
      "novelty_score": 0.9,
      "analysis": "Introduces quantum decoherence concept not seen in previous cycles"
    }

    Example (partial overlap):
    If current: "Local entropy applies primarily below Planck scale"
    And cycle 5 had: "Entropy increases locally in quantum systems":
    Valid response:
    {
      "is_retread": false,
      "similar_claims": ["Entropy increases locally in quantum systems"],
      "cycle_numbers": [5],
      "novelty_score": 0.6,
      "analysis": "Overlaps concept of local entropy but introduces Planck scale specificity"
    }

    Respond with valid JSON only.
    """
  end

  def build_prompt(%Server{current_claim: claim}) do
    """
    You are analyzing current claim for re-treading of previous positions.

    Current claim:
    #{claim}

    WARNING: No blackboard_id available. Cannot access historical claims for comparison.

    Your task:
    1. Note that historical comparison is not possible.
    2. Provide placeholder analysis.

    Required response format (JSON):
    {
      "is_retread": false,
      "similar_claims": [],
      "cycle_numbers": [],
      "novelty_score": 0.5,
      "analysis": "Historical comparison not available - no blackboard_id"
    }

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts retread analysis.

  Returns a map with:
  - is_retread: boolean indicating if this is a re-tread
  - similar_claims: list of similar claim texts
  - cycle_numbers: list of cycle numbers with similar claims
  - novelty_score: float from 0.0 to 1.0
  - analysis: explanation (optional)
  - valid: boolean indicating if the response was properly formatted
  - error: error message if invalid
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "is_retread" => is_retread,
         "similar_claims" => similar_claims,
         "cycle_numbers" => cycle_numbers,
         "novelty_score" => novelty_score
       } = data} ->
        build_response_map(is_retread, similar_claims, cycle_numbers, novelty_score, data)

      {:ok, _partial} ->
        error_response(
          "Missing required fields: is_retread, similar_claims, cycle_numbers, and novelty_score"
        )

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(boolean(), list(), list(), float(), map()) :: map()
  defp build_response_map(is_retread, similar_claims, cycle_numbers, novelty_score, data) do
    base = %{
      is_retread: is_retread,
      similar_claims: similar_claims,
      cycle_numbers: cycle_numbers,
      novelty_score: novelty_score,
      analysis: Map.get(data, "analysis", "")
    }

    cond do
      not is_boolean(is_retread) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "is_retread must be a boolean")

      not is_list(similar_claims) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "similar_claims must be a list")

      not is_list(cycle_numbers) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "cycle_numbers must be a list")

      not is_number(novelty_score) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "novelty_score must be a number")

      novelty_score < 0.0 or novelty_score > 1.0 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "novelty_score must be between 0.0 and 1.0")

      true ->
        Map.put(base, :valid, true)
    end
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      is_retread: false,
      similar_claims: [],
      cycle_numbers: [],
      novelty_score: 0.5,
      analysis: "",
      valid: false,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Historian agent.

  The Historian is advisory only and returns 0 confidence delta.
  It flags retreads but does not directly impact confidence.
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(%{valid: true}), do: 0.0

  def confidence_delta(%{valid: false}), do: 0.0

  @spec fetch_previous_claims(pos_integer() | nil, non_neg_integer(), atom()) :: list(map())
  defp fetch_previous_claims(_blackboard_id, current_cycle, blackboard_name) do
    from_cycle = 0
    to_cycle = max(0, current_cycle - 1)

    snapshots = Server.get_snapshots(blackboard_name, from_cycle, to_cycle)

    extract_claims_from_snapshots(snapshots)
  end

  @spec extract_claims_from_snapshots(list() | {:error, term()}) :: list(map())
  defp extract_claims_from_snapshots([]), do: []

  defp extract_claims_from_snapshots({:error, _reason}), do: []

  defp extract_claims_from_snapshots(snapshots) when is_list(snapshots) do
    snapshots
    |> Enum.filter(&has_valid_state_json?/1)
    |> Enum.map(&snapshot_to_claim_map/1)
    |> Enum.filter(&non_empty_claim?/1)
  end

  @spec has_valid_state_json?(map()) :: boolean()
  defp has_valid_state_json?(snapshot) do
    is_map(snapshot) and is_map(snapshot.state_json)
  end

  @spec snapshot_to_claim_map(map()) :: map()
  defp snapshot_to_claim_map(snapshot) do
    %{
      cycle_number: snapshot.cycle_number,
      claim:
        Map.get(snapshot.state_json, :current_claim) ||
          Map.get(snapshot.state_json, "current_claim")
    }
  end

  @spec non_empty_claim?(map()) :: boolean()
  defp non_empty_claim?(%{claim: claim}) do
    not is_nil(claim) and claim != ""
  end
end
