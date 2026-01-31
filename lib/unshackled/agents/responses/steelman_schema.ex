defmodule Unshackled.Agents.Responses.SteelmanSchema do
  @moduledoc """
  Ecto embedded schema for validating Steelman agent responses.

  Validates that responses contain:
  - counter_argument: strongest counter-argument, presented neutrally (required)
  - key_assumptions: list of assumptions (required)
  - strongest_point: single most compelling point (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  @advocating_indicators ~w(
    therefore
    thus
    so
    consequently
    hence
    "i believe"
    "i argue"
    "i contend"
    "must be"
    "should be"
    "proves that"
    "demonstrates that"
    "clearly shows"
    undoubtedly
  )

  embedded_schema do
    field(:counter_argument, :string)
    field(:key_assumptions, {:array, :string})
    field(:strongest_point, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, the counter_argument uses neutral language
  (not advocating), and key_assumptions is a non-empty list.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:counter_argument, :key_assumptions, :strongest_point])
    |> validate_required([:counter_argument, :key_assumptions, :strongest_point])
    |> validate_min_length(:counter_argument, 20)
    |> validate_min_length(:strongest_point, 10)
    |> validate_no_advocating_language()
    |> validate_non_empty_list(:key_assumptions)
  end

  @spec validate_no_advocating_language(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_no_advocating_language(changeset) do
    argument = get_change(changeset, :counter_argument)

    if argument && contains_advocating?(argument) do
      add_error(
        changeset,
        :counter_argument,
        "Response advocates for counter-argument rather than constructing it"
      )
    else
      changeset
    end
  end

  @spec contains_advocating?(String.t()) :: boolean()
  defp contains_advocating?(text) do
    lowered = String.downcase(text)

    Enum.any?(@advocating_indicators, fn indicator ->
      matches_word_boundary?(lowered, indicator)
    end)
  end

  @spec matches_word_boundary?(String.t(), String.t()) :: boolean()
  defp matches_word_boundary?(text, pattern) do
    pattern_with_boundaries = "\\b#{Regex.escape(pattern)}\\b"

    case Regex.compile(pattern_with_boundaries, [:caseless]) do
      {:ok, regex} -> Regex.match?(regex, text)
      {:error, _} -> false
    end
  end

  @spec validate_non_empty_list(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_non_empty_list(changeset, field) do
    list = get_change(changeset, field)

    if list == nil or length(list) == 0 do
      add_error(changeset, field, "must be a non-empty list")
    else
      changeset
    end
  end
end
