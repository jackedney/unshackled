defmodule Unshackled.Agents.Perturber do
  @moduledoc """
  Perturber agent that injects frontier ideas into debate.

  The Perturber is scheduled with 20% probability per cycle and selects
  an eligible frontier idea to pivot debate in a new direction.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server
  require Logger

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :perturber
  def role, do: :perturber

  @doc """
  Builds a prompt from current blackboard state.

  Selects a frontier idea from the eligible pool (2+ sponsors, not activated)
  using weighted selection (more sponsors + younger = higher weight).

  If no eligible frontier exists, returns a skip response.

  Note: The scheduler controls activation probability (20% per cycle).
  This agent always executes when scheduled.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(
        %Server{blackboard_id: blackboard_id, blackboard_name: blackboard_name} = _state
      ) do
    handle_activated_case(blackboard_name, blackboard_id)
  end

  @spec handle_activated_case(atom() | nil, pos_integer() | nil) :: String.t()
  defp handle_activated_case(blackboard_name, blackboard_id) do
    case Server.select_weighted_frontier(blackboard_name) do
      nil ->
        require Logger
        Logger.warning("Perturber: No eligible frontier ideas in pool - skipping activation")
        build_skip_response()

      frontier_idea ->
        activate_frontier_and_build_prompt(frontier_idea, blackboard_name, blackboard_id)
    end
  end

  @spec activate_frontier_and_build_prompt(map(), atom() | nil, pos_integer() | nil) :: String.t()
  defp activate_frontier_and_build_prompt(frontier_idea, blackboard_name, blackboard_id) do
    case Server.activate_frontier(blackboard_name, frontier_idea.id) do
      :ok ->
        Logger.info(
          metadata: [agent_role: :perturber],
          message:
            "Perturber activated - selected frontier idea: #{String.slice(frontier_idea.idea_text, 0, 60)}... (sponsors: #{Map.get(frontier_idea, :sponsor_count)}, cycles alive: #{Map.get(frontier_idea, :cycles_alive)})"
        )

        build_pivot_prompt(frontier_idea.idea_text, blackboard_id)

      {:error, reason} ->
        Logger.warning(
          metadata: [agent_role: :perturber],
          message: "Failed to activate frontier: #{reason} - skipping"
        )

        build_skip_response()
    end
  end

  @spec build_pivot_prompt(String.t(), pos_integer() | nil) :: String.t()
  defp build_pivot_prompt(frontier_idea_text, _blackboard_id) do
    """
    You are pivoting the current debate using a frontier idea.

    Frontier idea: #{frontier_idea_text}

    Your task:
    1. Use the frontier idea to generate a NEW claim that pivots the debate.
    2. The pivot claim must be a DIRECT extension or consequence of the frontier idea.
    3. Explain how this pivot claim connects to the previous debate direction.
    4. Provide a clear rationale for why this pivot is strategically valuable.

    CRITICAL: The frontier idea is your PRIMARY guide. Your pivot must flow from it.

    Required response format (JSON):
    {
      "pivot_claim": "The new claim derived from the frontier idea",
      "connection_to_previous": "Explanation of how this pivot relates to previous debate",
      "pivot_rationale": "Why this pivot is strategically valuable"
    }

    Examples:

    Frontier: "Consider quantum decoherence effects"
    Valid response:
    {
      "pivot_claim": "Quantum decoherence destroys coherence at the nanosecond scale, preventing sustained thermodynamic gradients",
      "connection_to_previous": "This pivot challenges the local thermodynamics claim by introducing quantum mechanical time limits",
      "pivot_rationale": "Decoherence provides a principled boundary condition that was absent from the previous debate"
    }

    Frontier: "What if entropy is observer-dependent?"
    Valid response:
    {
      "pivot_claim": "Entropy measurements vary across reference frames, suggesting the second law is relational not absolute",
      "connection_to_previous": "This pivot reframes thermodynamic claims as observer-context dependent",
      "pivot_rationale": "Relational entropy opens new domains for testing (quantum vs classical observers)"
    }

    Invalid response (vague):
    {
      "pivot_claim": "Maybe we should think about this differently",
      "connection_to_previous": "It changes things",
      "pivot_rationale": "Because it's interesting"
    }

    Respond with valid JSON only.
    """
  end

  @spec build_skip_response() :: String.t()
  defp build_skip_response do
    """
    Perturber not activated or no eligible frontier ideas. Skip this cycle.
    """
  end

  @doc """
  Parses the LLM response and extracts pivot claim, connection, and rationale.

  Returns a map with:
  - pivot_claim: the new claim derived from frontier idea
  - connection_to_previous: explanation of pivot's relation to previous debate
  - pivot_rationale: strategic rationale for the pivot
  - valid: boolean indicating if response was properly formatted
  - activated: boolean indicating if perturber was activated

  Skip responses (when not activated or no frontier) are marked with activated: false.
  Invalid responses are flagged if:
  - Malformed JSON
  - Missing required fields
  - Pivot claim, connection, or rationale are too short/vague
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    if String.contains?(response, "Skip this cycle") do
      %{
        pivot_claim: nil,
        connection_to_previous: nil,
        pivot_rationale: nil,
        valid: true,
        activated: false
      }
    else
      parse_json_response(response)
    end
  end

  @spec parse_json_response(String.t()) :: map()
  defp parse_json_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "pivot_claim" => claim,
         "connection_to_previous" => connection,
         "pivot_rationale" => rationale
       } = data} ->
        build_response_map(claim, connection, rationale, data)

      {:ok, _partial} ->
        error_response(
          "Missing required fields: pivot_claim, connection_to_previous, and pivot_rationale"
        )

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(String.t(), String.t(), String.t(), map()) :: map()
  defp build_response_map(claim, connection, rationale, _data) do
    base = %{
      pivot_claim: claim,
      connection_to_previous: connection,
      pivot_rationale: rationale,
      activated: true
    }

    cond do
      String.length(String.trim(claim)) < 10 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Pivot claim is too short - must provide meaningful new claim")

      String.length(String.trim(connection)) < 15 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Connection to previous is too short - must explain relationship")

      String.length(String.trim(rationale)) < 15 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Pivot rationale is too short - must explain strategic value")

      true ->
        Map.put(base, :valid, true)
    end
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      pivot_claim: nil,
      connection_to_previous: nil,
      pivot_rationale: nil,
      valid: false,
      activated: true,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Perturber agent.

  The Perturber creates a new claim that starts at 0.5 support,
  so it returns 0 (no delta applied to existing support).
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(%{activated: true}), do: 0.0

  def confidence_delta(%{activated: false}), do: 0.0
end
