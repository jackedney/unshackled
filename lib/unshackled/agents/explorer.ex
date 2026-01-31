defmodule Unshackled.Agents.Explorer do
  @moduledoc """
  Explorer agent that extends claims by one inferential step.

  The Explorer agent takes the current claim and extends it logically
  by one step using deductive, inductive, or abductive reasoning.
  """

  @behaviour Unshackled.Agents.Agent

  alias Unshackled.Agents.Agent
  alias Unshackled.Agents.PromptBuilder
  alias Unshackled.Agents.Responses.ExplorerSchema
  alias Unshackled.Blackboard.Server
  import Ecto.Changeset

  @hedging_words [
    "might",
    "possibly",
    "perhaps",
    "maybe",
    "could be",
    "seems",
    "appears",
    "likely",
    "probably",
    "would seem"
  ]

  @doc """
  Returns the agent's role.
  """
  @impl true
  @spec role() :: :explorer
  def role, do: :explorer

  @doc """
  Builds a prompt from the current blackboard state.

  The prompt instructs the LLM to extend the claim by one inferential step
  and commit to the extension without hedging.
  """
  @impl true
  @spec build_prompt(Server.t()) :: String.t()
  def build_prompt(server) do
    ctx = PromptBuilder.extract_context(server)
    claim = ctx.current_claim
    support = ctx.support_strength

    """
    You are extending the following claim by exactly one inferential step.

    Current claim: #{claim}
    Current support strength: #{Float.round(support, 2)}

    Your task:
    1. Take the current claim and extend it logically by one step.
    2. Use deductive, inductive, or abductive reasoning.
    3. Commit to your extension absolutely. Do NOT hedge, qualify, or use uncertain language.
    4. State your new claim definitively.

    FORBIDDEN language (any use invalidates your response):
    - "might", "possibly", "perhaps", "maybe"
    - "could be", "seems", "appears"
    - "likely", "probably", "would seem"

    #{PromptBuilder.json_instructions(%{new_claim: "Your definitive extension of the claim", inference_type: "deductive|inductive|abductive", reasoning: "Brief explanation of the inference"})}

    CRITICAL: The new_claim must start with the SUBJECT of the claim (a noun phrase), NOT a transitional word.
    NEVER begin with: "Therefore", "Consequently", "Thus", "Hence", "As a result", "Accordingly", "So", "In conclusion".
    These transitional words are FORBIDDEN as opening words.

    Example:
    If given: "Entropy increases locally"
    Valid response:
    {
      "new_claim": "Heat flows from hot to cold in isolated regions due to local entropy increase",
      "inference_type": "deductive",
      "reasoning": "Local entropy increase implies thermodynamic gradients cause heat flow"
    }

    Invalid response (starts with transitional word):
    {
      "new_claim": "Therefore heat flows from hot to cold in isolated regions",
      "inference_type": "deductive",
      "reasoning": "..."
    }
    Error: Claim starts with "Therefore" - must start with the subject

    Invalid response (contains hedging):
    {
      "new_claim": "Heat might flow from hot to cold in some cases",
      "inference_type": "deductive",
      "reasoning": "..."
    }

    Respond with valid JSON only.
    """
  end

  @doc """
  Parses the LLM response and validates it against the Explorer schema.

  Returns {:ok, %ExplorerSchema{}} on valid response.
  Returns {:error, changeset} on invalid response (missing fields, invalid inference_type, hedging, etc.).
  """
  @impl true
  @spec parse_response(String.t()) :: {:ok, ExplorerSchema.t()} | {:error, Ecto.Changeset.t()}
  def parse_response(response) do
    case Agent.decode_json_response(response) do
      {:ok, data} ->
        build_response_from_data(data)

      {:error, _reason} ->
        schema = %ExplorerSchema{}
        changeset = ExplorerSchema.changeset(schema, %{})
        {:error, add_error(changeset, :json, "Invalid JSON format")}
    end
  end

  @spec build_response_from_data(map()) ::
          {:ok, ExplorerSchema.t()} | {:error, Ecto.Changeset.t()}
  defp build_response_from_data(data) do
    attrs = %{
      new_claim: Map.get(data, "new_claim"),
      inference_type: Map.get(data, "inference_type"),
      reasoning: Map.get(data, "reasoning", "")
    }

    schema = %ExplorerSchema{}
    changeset = ExplorerSchema.changeset(schema, attrs)

    if changeset.valid? do
      schema_with_data = apply_changes(changeset)
      apply_custom_validations(schema_with_data, data)
    else
      {:error, changeset}
    end
  end

  @spec apply_custom_validations(ExplorerSchema.t(), map()) ::
          {:ok, ExplorerSchema.t()} | {:error, Ecto.Changeset.t()}
  defp apply_custom_validations(schema, data) do
    claim = Map.get(data, "new_claim")

    changeset =
      change(schema, %{})
      |> validate_custom_rules(claim)

    if changeset.valid? do
      updated_schema = apply_changes(changeset)
      {:ok, updated_schema}
    else
      {:error, changeset}
    end
  end

  @spec validate_custom_rules(Ecto.Changeset.t(), String.t() | nil) :: Ecto.Changeset.t()
  defp validate_custom_rules(changeset, claim) when is_binary(claim) do
    cleaned_claim = strip_transitional_prefix(claim)

    changeset
    |> put_change(:new_claim, cleaned_claim)
    |> validate_no_hedging(cleaned_claim)
  end

  defp validate_custom_rules(changeset, _claim), do: changeset

  @spec validate_no_hedging(Ecto.Changeset.t(), String.t()) :: Ecto.Changeset.t()
  defp validate_no_hedging(changeset, claim) do
    if contains_hedging?(claim) do
      add_error(
        changeset,
        :new_claim,
        "Hedging detected: must commit to extension without uncertainty"
      )
    else
      changeset
    end
  end

  @doc """
  Returns the confidence delta for the Explorer agent.

  The Explorer suggests +0.10 confidence boost if its extension
  survives the Critic's review.
  """
  @impl true
  @spec confidence_delta(map() | {:ok, ExplorerSchema.t()} | {:error, Ecto.Changeset.t()}) ::
          float()
  def confidence_delta({:ok, _schema}), do: 0.10

  def confidence_delta({:error, _changeset}), do: 0.0

  def confidence_delta(%{valid: true}), do: 0.10

  def confidence_delta(%{valid: false}), do: 0.0

  def confidence_delta(_), do: 0.0

  @spec contains_hedging?(String.t()) :: boolean()
  defp contains_hedging?(text) when is_binary(text) do
    lower_text = String.downcase(text)
    Enum.any?(@hedging_words, fn word -> String.contains?(lower_text, word) end)
  end

  defp contains_hedging?(_), do: false

  # Sorted by length descending so longer matches are tried first
  @transitional_prefixes [
    "in conclusion",
    "as a result",
    "consequently",
    "accordingly",
    "ultimately",
    "therefore",
    "finally",
    "hence",
    "thus",
    "so"
  ]

  @spec strip_transitional_prefix(String.t()) :: String.t()
  defp strip_transitional_prefix(text) when is_binary(text) do
    trimmed = String.trim(text)
    lower = String.downcase(trimmed)

    Enum.reduce_while(@transitional_prefixes, trimmed, fn prefix, acc ->
      if String.starts_with?(lower, prefix) do
        # Find the actual text after the prefix
        prefix_len = String.length(prefix)
        rest = String.slice(acc, prefix_len..-1//1)

        # Strip leading punctuation and whitespace (comma, colon, etc.)
        cleaned = String.replace(rest, ~r/^[\s,;:]+/, "")

        # Capitalize the first letter
        result =
          case String.first(cleaned) do
            nil -> cleaned
            first -> String.upcase(first) <> String.slice(cleaned, 1..-1//1)
          end

        {:halt, result}
      else
        {:cont, acc}
      end
    end)
  end

  defp strip_transitional_prefix(text), do: text
end
