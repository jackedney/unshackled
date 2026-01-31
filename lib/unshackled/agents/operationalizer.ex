defmodule Unshackled.Agents.Operationalizer do
  @moduledoc """
  Operationalizer agent that converts claims to falsifiable predictions.

  The Operationalizer agent takes the current claim and converts it into
  a testable, falsifiable prediction. The prediction must be surprising
  - something that would only be observed if the claim is true.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Blackboard.Server

  @obvious_prediction_indicators [
    "regardless of",
    "in any case",
    "would happen anyway",
    "expected behavior",
    "normal outcome",
    "standard observation",
    "typical result",
    "common knowledge",
    "well known fact"
  ]

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :operationalizer
  def role, do: :operationalizer

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to create a testable, falsifiable prediction
  that is surprising and would only be observed if the claim is true.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{current_claim: claim}) do
    """
    You are converting the following claim into a testable, falsifiable prediction.

    Current claim: #{claim}

    Your task:
    1. Translate the claim into a specific, observable prediction.
    2. Specify the exact conditions under which the observation should occur.
    3. Describe what would be observed if the claim is true.
    4. Ensure the prediction is SURPRISING - something that would NOT happen if the claim were false.

    CRITICAL: The prediction must be SURPRISING (non-obvious)
    - The observation must distinguish between the claim being true vs false
    - Avoid predictions that would be expected regardless of the claim
    - The more surprising the prediction, the more powerful the test

    Required response format (JSON):
    {
      "prediction": "Full prediction following format 'If true, observe X under Y'",
      "test_conditions": "Specific conditions under which to make the observation",
      "expected_observation": "What would be observed if the claim is true",
      "surprise_factor": "Explanation of why this prediction is surprising/non-obvious"
    }

    Examples:

    Example 1 - Local thermodynamics claim:
    {
      "prediction": "If local thermodynamics holds, we should observe entropy decrease in systems smaller than 10^-9 meters under conditions of isolation",
      "test_conditions": "Isolated quantum systems at nanometer scales, initial entropy measured, system allowed to evolve for 100 nanoseconds",
      "expected_observation": "Measurable decrease in entropy (≥5%) within the isolated nanoscale system, contrary to the universal second law",
      "surprise_factor": "This would be surprising because standard thermodynamics predicts entropy never decreases in any system. Observing a decrease at small scales would fundamentally contradict the universal law."
    }

    Example 2 - Faster-than-light communication claim:
    {
      "prediction": "If FTL communication is possible, we should observe information transfer between entangled particles exceeding the speed of light",
      "test_conditions": "Entangled particle pair separated by 10 kilometers, measurement performed on particle A at time T, particle B measured simultaneously",
      "expected_observation": "State of particle B instantaneously correlated with measurement of A, with no detectable time delay (Δt < 10^-12 seconds)",
      "surprise_factor": "This would be surprising because relativity forbids information transfer faster than light speed. Instant correlation would violate causality as currently understood."
    }

    Invalid prediction (obvious, would happen anyway):
    {
      "prediction": "If local thermodynamics holds, we should observe heat flow",
      "test_conditions": "Heat source and sink present",
      "expected_observation": "Heat flows from hot to cold",
      "surprise_factor": "This is just normal thermodynamics - would happen regardless"
    }

    Invalid prediction (not surprising):
    {
      "prediction": "If the claim is true, we should observe typical behavior",
      "test_conditions": "Normal conditions",
      "expected_observation": "Expected result",
      "surprise_factor": "This is expected behavior regardless of the claim"
    }

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts the prediction, test conditions, expected observation, and surprise factor.

  Returns a map with:
  - prediction: the falsifiable prediction
  - test_conditions: specific conditions for observation
  - expected_observation: what would be observed if claim is true
  - surprise_factor: explanation of why prediction is surprising
  - valid: boolean indicating if the response was properly formatted

  Invalid responses are flagged if:
  - Contains obvious prediction indicators (would happen anyway)
  - Missing required fields
  - Malformed JSON
  """
  @impl true
  @spec parse_response(String.t()) :: map()
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok,
       %{
         "prediction" => prediction,
         "test_conditions" => conditions,
         "expected_observation" => observation,
         "surprise_factor" => surprise
       } = data} ->
        build_response_map(prediction, conditions, observation, surprise, data)

      {:ok, _partial} ->
        error_response(
          "Missing required fields: prediction, test_conditions, expected_observation, and surprise_factor"
        )

      {:error, _} ->
        error_response("Invalid JSON format")
    end
  end

  @spec build_response_map(String.t(), String.t(), String.t(), String.t(), map()) :: map()
  defp build_response_map(prediction, conditions, observation, surprise, _data) do
    base = %{
      prediction: prediction,
      test_conditions: conditions,
      expected_observation: observation,
      surprise_factor: surprise
    }

    cond do
      contains_obvious_prediction?(prediction) or contains_obvious_prediction?(surprise) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Prediction is obvious - would be expected regardless of claim truth")

      not contains_if_true_format?(prediction) ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Prediction must follow format 'If true, observe X under Y'")

      String.length(String.trim(prediction)) < 20 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Prediction is too short - must provide specific falsifiable prediction"
        )

      String.length(String.trim(conditions)) < 10 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(:error, "Test conditions are too short - must specify exact conditions")

      String.length(String.trim(observation)) < 10 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Expected observation is too short - must describe what would be observed"
        )

      String.length(String.trim(surprise)) < 20 ->
        base
        |> Map.put(:valid, false)
        |> Map.put(
          :error,
          "Surprise factor is too short - must explain why prediction is surprising"
        )

      true ->
        Map.put(base, :valid, true)
    end
  end

  @spec error_response(String.t()) :: map()
  defp error_response(message) do
    %{
      prediction: nil,
      test_conditions: nil,
      expected_observation: nil,
      surprise_factor: nil,
      valid: false,
      error: message
    }
  end

  @doc """
  Returns the confidence delta for the Operationalizer agent.

  The Operationalizer has no direct confidence impact - it provides
  testable predictions for verification by other means.
  """
  @impl true
  @spec confidence_delta(map()) :: float()
  def confidence_delta(_), do: 0.0

  @spec contains_obvious_prediction?(String.t()) :: boolean()
  defp contains_obvious_prediction?(text) when is_binary(text) do
    lower_text = String.downcase(text)

    Enum.any?(@obvious_prediction_indicators, fn indicator ->
      String.contains?(lower_text, indicator)
    end)
  end

  defp contains_obvious_prediction?(_), do: false

  @spec contains_if_true_format?(String.t()) :: boolean()
  defp contains_if_true_format?(text) when is_binary(text) do
    lower_text = String.downcase(text)

    if_check =
      String.starts_with?(lower_text, "if") or String.contains?(lower_text, "if ") or
        String.contains?(lower_text, "if the")

    observe_check =
      String.contains?(lower_text, "observe") or String.contains?(lower_text, "should observe")

    if_check and observe_check
  end

  defp contains_if_true_format?(_), do: false
end
