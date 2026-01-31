defmodule Unshackled.Agents.Responses.QuantifierSchema do
  @moduledoc """
  Ecto embedded schema for validating Quantifier agent responses.

  Validates that responses contain:
  - quantified_claim: claim with numerical bounds added (required)
  - bounds: description of numerical bounds or parameters added (required)
  - bounds_justification: detailed explanation of why these specific values were chosen (required)
  - arbitrary_flag: boolean indicating if bounds are arbitrary (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @arbitrary_without_acknowledgment_indicators ~w(
    "i think"
    "maybe"
    "approximately"
    "roughly"
    "about"
    "around"
    "somehow"
    "some value"
  )

  embedded_schema do
    field(:quantified_claim, :string)
    field(:bounds, :string)
    field(:bounds_justification, :string)
    field(:arbitrary_flag, :boolean)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, numerical values are present,
  and arbitrary bounds are properly acknowledged.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:quantified_claim, :bounds, :bounds_justification, :arbitrary_flag])
    |> validate_required([:quantified_claim, :bounds, :bounds_justification, :arbitrary_flag])
    |> validate_min_length(:quantified_claim, 15)
    |> validate_min_length(:bounds_justification, 30)
    |> validate_contains_numerical_value()
    |> validate_arbitrary_acknowledgment()
  end

  @spec validate_contains_numerical_value(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_contains_numerical_value(changeset) do
    claim = get_change(changeset, :quantified_claim)
    bounds = get_change(changeset, :bounds)

    has_numerical? =
      (claim and contains_numerical_value?(claim)) or
        (bounds and contains_numerical_value?(bounds))

    if not has_numerical? do
      add_error(
        changeset,
        :quantified_claim,
        "No numerical bounds or values detected - must add specific numbers"
      )
    else
      changeset
    end
  end

  @spec contains_numerical_value?(String.t()) :: boolean()
  defp contains_numerical_value?(text) do
    Regex.match?(~r/\d+(\.\d+)?|\d+[eE][+-]?\d+/, text)
  end

  @spec validate_arbitrary_acknowledgment(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_arbitrary_acknowledgment(changeset) do
    claim = get_change(changeset, :quantified_claim)
    justification = get_change(changeset, :bounds_justification)
    arbitrary_flag = get_change(changeset, :arbitrary_flag)

    cond do
      arbitrary_flag == true ->
        # Check if arbitrary language is acknowledged
        if has_arbitrary_language_without_acknowledgment?(claim, justification) do
          add_error(
            changeset,
            :arbitrary_flag,
            "Arbitrary bounds detected without proper acknowledgment in quantified_claim or justification"
          )
        else
          changeset
        end

      true ->
        changeset
    end
  end

  @spec has_arbitrary_language_without_acknowledgment?(String.t() | nil, String.t() | nil) ::
          boolean()
  defp has_arbitrary_language_without_acknowledgment?(nil, _), do: false
  defp has_arbitrary_language_without_acknowledgment?(_, nil), do: false

  defp has_arbitrary_language_without_acknowledgment?(claim, justification) do
    has_arbitrary_language? =
      contains_arbitrary_indicator?(claim) or contains_arbitrary_indicator?(justification)

    lacks_acknowledgment? =
      not contains_acknowledgment?(claim) and not contains_acknowledgment?(justification)

    has_arbitrary_language? and lacks_acknowledgment?
  end

  @spec contains_arbitrary_indicator?(String.t()) :: boolean()
  defp contains_arbitrary_indicator?(text) do
    lowered = String.downcase(text)

    Enum.any?(@arbitrary_without_acknowledgment_indicators, fn indicator ->
      String.contains?(lowered, indicator)
    end)
  end

  @spec contains_acknowledgment?(String.t()) :: boolean()
  defp contains_acknowledgment?(text) do
    lowered = String.downcase(text)
    String.contains?(lowered, "arbitrary") or String.contains?(lowered, "working hypothesis")
  end
end
