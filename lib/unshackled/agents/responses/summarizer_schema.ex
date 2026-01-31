defmodule Unshackled.Agents.Responses.SummarizerSchema do
  @moduledoc """
  Ecto embedded schema for validating Summarizer agent responses.

  Validates that responses contain:
  - full_context_summary: the claim with all implicit references made explicit (required)
  - evolution_narrative: 2-3 sentence narrative explaining claim's evolution (required)
  - addressed_objections: list of objections that have been addressed (required)
  - remaining_gaps: list of ambiguities or unresolved issues (required)
  """
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:full_context_summary, :string)
    field(:evolution_narrative, :string)
    field(:addressed_objections, {:array, :string})
    field(:remaining_gaps, {:array, :string})
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and lists are arrays.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :full_context_summary,
      :evolution_narrative,
      :addressed_objections,
      :remaining_gaps
    ])
    |> validate_required([
      :full_context_summary,
      :evolution_narrative,
      :addressed_objections,
      :remaining_gaps
    ])
    |> validate_list(:addressed_objections)
    |> validate_list(:remaining_gaps)
  end

  @spec validate_list(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_list(changeset, field) do
    list = get_change(changeset, field)

    if is_list(list) do
      changeset
    else
      add_error(changeset, field, "must be an array")
    end
  end
end
