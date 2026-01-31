defmodule Unshackled.Agents.Critic do
  @moduledoc """
  Critic agent that attacks weakest premise of claims.

  The Critic agent identifies the weakest premise in a claim,
  formulates a specific objection to that premise, and asks a
  clarifying question to probe the foundation.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Agents.PromptBuilder
  alias Unshackled.Agents.Responses.CriticSchema
  alias Unshackled.Blackboard.Server
  import Ecto.Changeset

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :critic
  def role, do: :critic

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to attack the weakest premise,
  not the conclusion, and to formulate a clarifying question.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(server) do
    ctx = PromptBuilder.extract_context(server)
    claim = ctx.current_claim

    """
     You are Attacking the weakest premise of the following claim.

    Current claim: #{claim}

    Your task:
    1. Identify the weakest premise or assumption underlying the claim.
    2. Formulate a specific objection to that premise.
    3. Ask a clarifying question that probes the foundation.

    CRITICAL: Attack the PREMISE, not the conclusion
    - PREMISE: The foundational assumption or claim component
    - CONCLUSION: The final assertion or result

    FORBIDDEN patterns (any use invalidates your response):
    - Objections targeting the final result or conclusion
    - General skepticism without specific premise focus
    - "This is wrong because..." without identifying which premise

    #{PromptBuilder.json_instructions(%{objection: "Your specific objection to a premise", target_premise: "The exact premise you are objecting to", clarifying_question: "A question probing this premise", reasoning: "Brief explanation of why this premise is weak"})}

    Example:
    If given: "Heat flows from hot to cold in isolated regions"
    Valid response:
    {
      "objection": "The concept of 'isolated regions' becomes ambiguous at quantum scales",
      "target_premise": "isolated regions",
      "clarifying_question": "What constitutes isolation at quantum scales where entanglement is pervasive?",
      "reasoning": "Quantum entanglement challenges the notion of isolation, making the premise unstable at small scales"
    }

    Invalid response (targets conclusion):
    {
      "objection": "This conclusion is not always true",
      "target_premise": "conclusion",
      "clarifying_question": "...",
      "reasoning": "..."
    }

    Invalid response (targets result):
    {
      "objection": "The result 'heat flows' is questionable",
      "target_premise": "heat flows",
      "clarifying_question": "...",
      "reasoning": "..."
    }

    Valid objection examples (targeting premises):
    - "isolated regions" → Premise that isolation is well-defined
    - "hot to cold" → Premise that temperature gradient is meaningful
    - "heat flows" → Premise that heat behaves as a fluid
    - "thermodynamic laws are universal" → Premise of universality

    Invalid objection examples (targeting conclusions/results):
    - "therefore" or "thus" → Rejecting the conclusion marker
    - "This is false" → Attacking the conclusion directly
    - "The claim is wrong" → General rejection without premise focus

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and validates it against the Critic schema.

  Returns {:ok, %CriticSchema{}} on valid response.
  Returns {:error, changeset} on invalid response (missing fields, targeting conclusion, etc.).
  """
  @impl true
  @spec parse_response(String.t()) :: {:ok, CriticSchema.t()} | {:error, Ecto.Changeset.t()}
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok, data} ->
        attrs = %{
          objection: Map.get(data, "objection"),
          target_premise: Map.get(data, "target_premise"),
          clarifying_question: Map.get(data, "clarifying_question"),
          reasoning: Map.get(data, "reasoning", "")
        }

        schema = %CriticSchema{}
        changeset = CriticSchema.changeset(schema, attrs)

        if changeset.valid? do
          schema_with_data = apply_changes(changeset)
          {:ok, schema_with_data}
        else
          {:error, changeset}
        end

      {:error, _reason} ->
        schema = %CriticSchema{}
        changeset = CriticSchema.changeset(schema, %{})
        {:error, add_error(changeset, :json, "Invalid JSON format")}
    end
  end

  @doc """
  Returns the confidence delta for the Critic agent.

  The Critic suggests -0.15 confidence penalty if its objection
  remains unanswered.
  """
  @impl true
  @spec confidence_delta({:ok, CriticSchema.t()} | {:error, Ecto.Changeset.t()}) :: float()
  def confidence_delta({:ok, _schema}), do: -0.15

  def confidence_delta({:error, _changeset}), do: 0.0
end
