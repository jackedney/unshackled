defmodule Unshackled.Agents.Responses.CriticSchema do
  @moduledoc """
  Ecto embedded schema for validating Critic agent responses.

  Validates that responses contain:
  - objection: specific objection to a premise (required)
  - target_premise: premise being objected to (required)
  - clarifying_question: probing question (required)
  - reasoning: explanation of why this premise is weak (optional)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @conclusion_indicators ~w(therefore thus consequently hence so "as a result")

  embedded_schema do
    field(:objection, :string)
    field(:target_premise, :string)
    field(:clarifying_question, :string)
    field(:reasoning, :string, default: "")
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and that the objection targets a premise,
  not the conclusion.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:objection, :target_premise, :clarifying_question, :reasoning])
    |> validate_required([:objection, :target_premise, :clarifying_question])
    |> validate_min_length(:objection, 10)
    |> validate_min_length(:target_premise, 5)
    |> validate_min_length(:clarifying_question, 10)
    |> validate_target_premise_not_conclusion()
  end

  @spec validate_target_premise_not_conclusion(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_target_premise_not_conclusion(changeset) do
    target_premise = get_change(changeset, :target_premise)

    if target_premise && is_conclusion_indicator?(target_premise) do
      add_error(
        changeset,
        :target_premise,
        "target_premise is a conclusion indicator, not an actual premise"
      )
    else
      changeset
    end
  end

  @spec is_conclusion_indicator?(String.t() | nil) :: boolean()
  defp is_conclusion_indicator?(nil), do: false

  defp is_conclusion_indicator?(premise) do
    lowered = String.downcase(String.trim(premise))

    Enum.any?(@conclusion_indicators, fn indicator ->
      lowered == indicator or String.starts_with?(lowered, indicator <> " ")
    end)
  end
end
