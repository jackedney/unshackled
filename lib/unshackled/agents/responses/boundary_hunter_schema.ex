defmodule Unshackled.Agents.Responses.BoundaryHunterSchema do
  @moduledoc """
  Ecto embedded schema for validating Boundary Hunter agent responses.

  Validates that responses contain:
  - edge_case: a specific, testable edge case or boundary condition (required)
  - why_it_breaks: explanation of how claim fails in this case (required)
  - consequence: paradox, contradiction, or failure that results (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @general_skepticism_phrases ~w(
    "we can never be sure"
    "cannot be proven"
    "impossible to verify"
    "always uncertain"
    "fundamentally unknowable"
    "beyond testing"
    "cannot confirm"
    "might be wrong"
    "could be false"
    "no way to know"
    "we cannot determine"
    "cannot establish"
    "impossible to establish"
    "cannot be certain"
  )

  embedded_schema do
    field(:edge_case, :string)
    field(:why_it_breaks, :string)
    field(:consequence, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and have sufficient length.
  Ensures the edge case is specific, not general skepticism.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:edge_case, :why_it_breaks, :consequence])
    |> validate_required([:edge_case, :why_it_breaks, :consequence])
    |> validate_min_length(:edge_case, 15)
    |> validate_min_length(:why_it_breaks, 15)
    |> validate_min_length(:consequence, 15)
    |> validate_no_general_skepticism()
  end

  @spec validate_no_general_skepticism(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_no_general_skepticism(changeset) do
    edge_case = get_change(changeset, :edge_case)
    why_breaks = get_change(changeset, :why_it_breaks)
    consequence = get_change(changeset, :consequence)

    changeset
    |> check_skepticism(
      :edge_case,
      edge_case,
      "Edge case contains general skepticism instead of specific boundary condition"
    )
    |> check_skepticism(
      :why_it_breaks,
      why_breaks,
      "Explanation contains general skepticism instead of specific mechanism"
    )
    |> check_skepticism(
      :consequence,
      consequence,
      "Consequence contains general skepticism instead of specific result"
    )
  end

  @spec check_skepticism(Ecto.Changeset.t(), atom(), String.t() | nil, String.t()) ::
          Ecto.Changeset.t()
  defp check_skepticism(changeset, _field, nil, _error_msg), do: changeset

  defp check_skepticism(changeset, field, text, error_msg) do
    if contains_skepticism?(text) do
      add_error(changeset, field, error_msg)
    else
      changeset
    end
  end

  @spec contains_skepticism?(String.t()) :: boolean()
  defp contains_skepticism?(text) do
    lowered = String.downcase(text)

    Enum.any?(@general_skepticism_phrases, fn phrase ->
      String.contains?(lowered, phrase)
    end)
  end
end
