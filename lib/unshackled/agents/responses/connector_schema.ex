defmodule Unshackled.Agents.Responses.ConnectorSchema do
  @moduledoc """
  Ecto embedded schema for validating Connector agent responses.

  Validates that responses contain:
  - analogy: the cross-domain analogy (required)
  - source_domain: domain the analogy draws from (required)
  - mapping_explanation: detailed explanation of the mapping (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @vague_analogy_indicators ~w(
    "many things in nature"
    "various phenomena"
    "similar to many"
    "like many things"
    "various aspects of"
    "numerous examples"
    "multiple cases"
  )

  embedded_schema do
    field(:analogy, :string)
    field(:source_domain, :string)
    field(:mapping_explanation, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, the analogy follows the "because" format,
  and is not too vague.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:analogy, :source_domain, :mapping_explanation])
    |> validate_required([:analogy, :source_domain, :mapping_explanation])
    |> validate_min_length(:analogy, 20)
    |> validate_min_length(:mapping_explanation, 30)
    |> validate_analogy_format()
    |> validate_no_vague_analogy()
  end

  @spec validate_analogy_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_analogy_format(changeset) do
    analogy = get_change(changeset, :analogy)

    if analogy && not contains_because?(analogy) do
      add_error(changeset, :analogy, "Analogy must follow format 'This is like X because Y'")
    else
      changeset
    end
  end

  @spec contains_because?(String.t()) :: boolean()
  defp contains_because?(text) do
    String.contains?(String.downcase(text), "because")
  end

  @spec validate_no_vague_analogy(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_no_vague_analogy(changeset) do
    analogy = get_change(changeset, :analogy)
    mapping = get_change(changeset, :mapping_explanation)

    changeset
    |> check_vague_analogy(:analogy, analogy)
    |> check_vague_analogy(:mapping_explanation, mapping)
  end

  @spec check_vague_analogy(Ecto.Changeset.t(), atom(), String.t() | nil) :: Ecto.Changeset.t()
  defp check_vague_analogy(changeset, _field, nil), do: changeset

  defp check_vague_analogy(changeset, field, text) do
    if contains_vague_indicator?(text) do
      add_error(changeset, field, "Contains vague analogy - must be specific and testable")
    else
      changeset
    end
  end

  @spec contains_vague_indicator?(String.t()) :: boolean()
  defp contains_vague_indicator?(text) do
    lowered = String.downcase(text)

    Enum.any?(@vague_analogy_indicators, fn indicator ->
      String.contains?(lowered, indicator)
    end)
  end
end
