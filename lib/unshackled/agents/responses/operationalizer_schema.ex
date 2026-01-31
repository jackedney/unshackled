defmodule Unshackled.Agents.Responses.OperationalizerSchema do
  @moduledoc """
  Ecto embedded schema for validating Operationalizer agent responses.

  Validates that responses contain:
  - prediction: full prediction following format 'If true, observe X under Y' (required)
  - test_conditions: specific conditions under which to make the observation (required)
  - expected_observation: what would be observed if claim is true (required)
  - surprise_factor: explanation of why this prediction is surprising/non-obvious (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @obvious_prediction_indicators ~w(
    "regardless of"
    "in any case"
    "would happen anyway"
    "expected behavior"
    "normal outcome"
    "standard observation"
    "typical result"
    "common knowledge"
    "well known fact"
  )

  embedded_schema do
    field(:prediction, :string)
    field(:test_conditions, :string)
    field(:expected_observation, :string)
    field(:surprise_factor, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, the prediction follows the "If true" format,
  and is not obvious.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:prediction, :test_conditions, :expected_observation, :surprise_factor])
    |> validate_required([:prediction, :test_conditions, :expected_observation, :surprise_factor])
    |> validate_min_length(:prediction, 20)
    |> validate_min_length(:test_conditions, 10)
    |> validate_min_length(:expected_observation, 10)
    |> validate_min_length(:surprise_factor, 20)
    |> validate_prediction_format()
    |> validate_not_obvious()
  end

  @spec validate_prediction_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_prediction_format(changeset) do
    prediction = get_change(changeset, :prediction)

    if prediction && not contains_if_true_format?(prediction) do
      add_error(
        changeset,
        :prediction,
        "Prediction must follow format 'If true, observe X under Y'"
      )
    else
      changeset
    end
  end

  @spec contains_if_true_format?(String.t()) :: boolean()
  defp contains_if_true_format?(text) do
    lowered = String.downcase(text)

    if_check =
      String.starts_with?(lowered, "if") or String.contains?(lowered, "if ") or
        String.contains?(lowered, "if,")

    observe_check =
      String.contains?(lowered, "observe") or String.contains?(lowered, "should observe")

    if_check and observe_check
  end

  @spec validate_not_obvious(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_not_obvious(changeset) do
    prediction = get_change(changeset, :prediction)
    surprise = get_change(changeset, :surprise_factor)

    changeset
    |> check_obvious(:prediction, prediction)
    |> check_obvious(:surprise_factor, surprise)
  end

  @spec check_obvious(Ecto.Changeset.t(), atom(), String.t() | nil) :: Ecto.Changeset.t()
  defp check_obvious(changeset, _field, nil), do: changeset

  defp check_obvious(changeset, field, text) do
    if contains_obvious_indicator?(text) do
      add_error(
        changeset,
        field,
        "Prediction is obvious - would be expected regardless of claim truth"
      )
    else
      changeset
    end
  end

  @spec contains_obvious_indicator?(String.t()) :: boolean()
  defp contains_obvious_indicator?(text) do
    lowered = String.downcase(text)

    Enum.any?(@obvious_prediction_indicators, fn indicator ->
      String.contains?(lowered, indicator)
    end)
  end
end
