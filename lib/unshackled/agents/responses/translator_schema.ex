defmodule Unshackled.Agents.Responses.TranslatorSchema do
  @moduledoc """
  Ecto embedded schema for validating Translator agent responses.

  Validates that responses contain:
  - translated_claim: claim restated using target framework's concepts (required)
  - target_framework: framework used for translation (required)
  - revealed_assumption: hidden assumption or structural feature revealed (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @valid_frameworks ~w(physics information_theory economics biology mathematics)

  @mere_rephrasing_patterns ~w(
    "basically means"
    "essentially" "same as"
    "is just another way of saying"
    "can be rephrased as"
    "is equivalent to stating"
    "similarly means"
  )

  embedded_schema do
    field(:translated_claim, :string)
    field(:target_framework, :string)
    field(:revealed_assumption, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, the target_framework is valid,
  the translation is not mere rephrasing, and has sufficient length.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:translated_claim, :target_framework, :revealed_assumption])
    |> validate_required([:translated_claim, :target_framework, :revealed_assumption])
    |> validate_min_length(:translated_claim, 20)
    |> validate_min_length(:revealed_assumption, 20)
    |> validate_target_framework()
    |> validate_no_mere_rephrasing()
  end

  @spec validate_target_framework(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_target_framework(changeset) do
    framework = get_change(changeset, :target_framework)

    if framework && framework not in @valid_frameworks do
      add_error(
        changeset,
        :target_framework,
        "must be one of: physics, information_theory, economics, biology, mathematics"
      )
    else
      changeset
    end
  end

  @spec validate_no_mere_rephrasing(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_no_mere_rephrasing(changeset) do
    translated_claim = get_change(changeset, :translated_claim)

    if translated_claim && contains_mere_rephrasing?(translated_claim) do
      add_error(
        changeset,
        :translated_claim,
        "Translation contains mere rephrasing patterns instead of framework-specific insight"
      )
    else
      changeset
    end
  end

  @spec contains_mere_rephrasing?(String.t()) :: boolean()
  defp contains_mere_rephrasing?(text) do
    lowered = String.downcase(text)

    Enum.any?(@mere_rephrasing_patterns, fn pattern ->
      String.contains?(lowered, pattern)
    end)
  end
end
