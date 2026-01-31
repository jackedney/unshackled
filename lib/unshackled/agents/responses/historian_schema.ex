defmodule Unshackled.Agents.Responses.HistorianSchema do
  @moduledoc """
  Ecto embedded schema for validating Historian agent responses.

  Validates that responses contain:
  - is_retread: boolean indicating if this is a re-tread (required)
  - similar_claims: list of similar claim texts (required)
  - cycle_numbers: list of cycle numbers with similar claims (required)
  - novelty_score: float from 0.0 to 1.0 (required)
  - analysis: explanation (optional, default "")
  """
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:is_retread, :boolean)
    field(:similar_claims, {:array, :string})
    field(:cycle_numbers, {:array, :integer})
    field(:novelty_score, :float)
    field(:analysis, :string, default: "")
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, lists are arrays,
  and novelty_score is within valid range.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:is_retread, :similar_claims, :cycle_numbers, :novelty_score, :analysis])
    |> validate_required([:is_retread, :similar_claims, :cycle_numbers, :novelty_score])
    |> validate_list(:similar_claims)
    |> validate_list(:cycle_numbers)
    |> validate_novelty_score_range()
  end

  @spec validate_list(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_list(changeset, field) do
    list = get_change(changeset, field)

    if is_list(list) do
      changeset
    else
      add_error(changeset, field, "must be a list")
    end
  end

  @spec validate_novelty_score_range(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_novelty_score_range(changeset) do
    score = get_change(changeset, :novelty_score)

    if is_number(score) and (score < 0.0 or score > 1.0) do
      add_error(changeset, :novelty_score, "must be between 0.0 and 1.0")
    else
      changeset
    end
  end
end
