defmodule Unshackled.Agents.Reducer do
  @moduledoc """
  Reducer agent that compresses claims to their fundamental essence.

  The Reducer agent takes a potentially verbose or elaborated claim and
  extracts its core logical content, removing unnecessary elaboration while
  preserving the essential logical structure.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Agents.Responses.ReducerSchema
  alias Unshackled.Blackboard.Server
  import Ecto.Changeset

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :reducer
  def role, do: :reducer

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to extract the essential claim by removing
  elaboration while preserving logical content.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(%Server{current_claim: claim}) do
    """
    You are reducing the following claim to its fundamental essence.

    Current claim: #{claim}

    Your task:
    1. Identify the core logical proposition at the heart of the claim.
    2. Remove all elaboration, examples, clarifications, and explanatory text.
    3. Preserve the essential logical content, relationships, and dependencies.
    4. State the essential claim in the clearest, most direct form possible.
    5. List what was removed and what was preserved.

    CRITICAL: You must preserve the logical content
    - Invalid: Removing key logical terms (e.g., "all", "only", "must", "cannot")
    - Invalid: Changing universal claims to existential claims
    - Invalid: Dropping necessary conditions or qualifiers
    - Valid: Removing examples, analogies, and illustrative language
    - Valid: Removing "I think," "In other words," and meta-commentary
    - Valid: Collapsing multi-sentence elaboration into single core proposition

    Required response format (JSON):
    {
      "essential_claim": "The distilled core proposition",
      "removed_elements": ["element 1", "element 2", ...],
      "preserved_elements": ["element 1", "element 2", ...]
    }

    Examples:

    Example 1 - Multi-sentence elaboration to single core:
    If given: "Local thermodynamics is possible because at the quantum scale, isolated systems can maintain coherence long enough for entropy decrease. This is supported by several experimental observations of quantum dots where energy spontaneously concentrates, suggesting that the second law is not absolute but probabilistic, allowing for rare fluctuations that reduce entropy temporarily."
    Valid response:
    {
      "essential_claim": "Isolated quantum systems can temporarily reduce entropy through rare fluctuations.",
      "removed_elements": [
        "Experimental observations of quantum dots",
        "Claim that second law is not absolute but probabilistic",
        "Explanation that energy spontaneously concentrates",
        "Elaboration on coherence duration"
      ],
      "preserved_elements": [
        "Isolated quantum systems",
        "Entropy can temporarily decrease",
        "Mechanism: rare fluctuations"
      ]
    }

    Example 2 - Removing examples and analogies:
    If given: "The system exhibits fractal behavior at multiple scales, similar to how coastlines look rough whether viewed from space or from the beach. This self-similarity means the same patterns repeat at different magnifications, like the branching of trees or the structure of blood vessels. Mathematically, this is characterized by a Hausdorff dimension between 1 and 2 for the coastline."
    Valid response:
    {
      "essential_claim": "The system exhibits self-similar patterns at multiple scales with fractal geometry.",
      "removed_elements": [
        "Analogy to coastlines",
        "Analogy to tree branching",
        "Analogy to blood vessels",
        "Specific Hausdorff dimension example"
      ],
      "preserved_elements": [
        "Self-similar patterns",
        "Multiple scales",
        "Fractal geometry"
      ]
    }

    Example 3 - Removing meta-commentary and hedging:
    If given: "I would argue that perhaps the fundamental constants might be contingent upon initial conditions rather than being determined by deeper physical principles. In other words, what we consider universal parameters could be the result of specific cosmic accidents that occurred during the early universe."
    Valid response:
    {
      "essential_claim": "Fundamental constants are contingent upon initial cosmic conditions rather than deeper principles.",
      "removed_elements": [
        "Meta-commentary 'I would argue'",
        "Hedging language 'might be', 'perhaps'",
        "Meta-commentary 'In other words'",
        "Elaboration on cosmic accidents"
      ],
      "preserved_elements": [
        "Fundamental constants are contingent",
        "Dependence on initial conditions",
        "Not determined by deeper principles"
      ]
    }

    Example 4 - Preserving logical quantifiers:
    If given: "For all quantum systems above a certain energy threshold, entanglement cannot be sustained beyond 10^-15 seconds due to decoherence effects from environmental interactions. This universal limitation applies regardless of the system's size or composition, provided the threshold condition is met."
    Valid response:
    {
      "essential_claim": "All quantum systems above the energy threshold lose entanglement within 10^-15 seconds due to decoherence.",
      "removed_elements": [
        "Explanation of environmental interactions",
        "Statement that limitation applies regardless of size/composition",
        "Elaboration on threshold condition"
      ],
      "preserved_elements": [
        "Universal quantifier 'all'",
        "Energy threshold condition",
        "Entanglement loss timeframe",
        "Decoherence mechanism"
      ]
    }

    Invalid response (loses key logical content):
    {
      "essential_claim": "Quantum systems lose entanglement quickly.",
      "removed_elements": [...],
      "preserved_elements": [...]
    }
    Error: Lost universal quantifier "all," lost threshold condition, lost specific timeframe

    Invalid response (preserves examples as if they were essential):
    {
      "essential_claim": "The system is fractal like coastlines and trees with Hausdorff dimension 1-2.",
      "removed_elements": [...],
      "preserved_elements": [...]
    }
    Error: Analogies and specific example preserved as if essential content

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and extracts the essential claim and the lists
  of removed and preserved elements.

  Returns a map with:
  - essential_claim: the distilled core proposition
  - removed_elements: list of elements removed during reduction
  - preserved_elements: list of elements preserved in the reduction
  - valid: boolean indicating if the response was properly formatted

  Invalid responses are flagged if:
  - Missing required fields
  - Malformed JSON
  - Lists are not arrays
  """
  @impl true
  @spec parse_response(String.t()) :: {:ok, ReducerSchema.t()} | {:error, Ecto.Changeset.t()}
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok, data} ->
        attrs = %{
          essential_claim: Map.get(data, "essential_claim"),
          removed_elements: Map.get(data, "removed_elements"),
          preserved_elements: Map.get(data, "preserved_elements")
        }

        schema = %ReducerSchema{}
        changeset = ReducerSchema.changeset(schema, attrs)

        if changeset.valid? do
          schema_with_data = apply_changes(changeset)
          {:ok, schema_with_data}
        else
          {:error, changeset}
        end

      {:error, _reason} ->
        schema = %ReducerSchema{}
        changeset = ReducerSchema.changeset(schema, %{})
        {:error, add_error(changeset, :json, "Invalid JSON format")}
    end
  end

  @doc """
  Returns to confidence delta for Reducer agent.

  The Reducer has no direct confidence impact (returns 0.0).
  The role is purely to distill claims without affecting confidence.
  """
  @impl true
  @spec confidence_delta({:ok, ReducerSchema.t()} | {:error, Ecto.Changeset.t()}) :: float()
  def confidence_delta({:ok, _schema}), do: 0.0

  def confidence_delta({:error, _changeset}), do: 0.0
end
