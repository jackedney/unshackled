defmodule Unshackled.Agents.Responses.GraveKeeperSchema do
  @moduledoc """
  Ecto embedded schema for validating Grave Keeper agent responses.

  Validates that responses contain:
  - death_risk: float from 0.0 to 1.0 indicating risk level (required)
  - similar_deaths: list of similar death records (required)
  - pattern_detected: string describing detected death pattern (required)
  - survival_suggestion: string with specific modification advice (required)
  """
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field(:death_risk, :float)
    field(:similar_deaths, :map)
    field(:pattern_detected, :string)
    field(:survival_suggestion, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present, death_risk is within valid range,
  and similar_deaths contains valid entries.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:death_risk, :similar_deaths, :pattern_detected, :survival_suggestion])
    |> validate_required([:death_risk, :similar_deaths, :pattern_detected, :survival_suggestion])
    |> validate_death_risk_range()
    |> validate_similar_deaths()
  end

  @spec validate_death_risk_range(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_death_risk_range(changeset) do
    risk = get_change(changeset, :death_risk)

    if is_number(risk) and (risk < 0.0 or risk > 1.0) do
      add_error(changeset, :death_risk, "must be between 0.0 and 1.0")
    else
      changeset
    end
  end

  @spec validate_similar_deaths(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_similar_deaths(changeset) do
    similar_deaths = get_change(changeset, :similar_deaths)

    if is_map(similar_deaths) do
      validate_death_entries(changeset, similar_deaths)
    else
      add_error(changeset, :similar_deaths, "must be a list")
    end
  end

  @spec validate_death_entries(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  defp validate_death_entries(changeset, similar_deaths) do
    Enum.reduce_while(similar_deaths, changeset, fn {_key, death}, acc_changeset ->
      if valid_death_entry?(death) do
        {:cont, acc_changeset}
      else
        {:halt, add_error(acc_changeset, :similar_deaths, "contains invalid entries")}
      end
    end)
  end

  @spec valid_death_entry?(map()) :: boolean()
  defp valid_death_entry?(death) do
    is_map(death) and
      is_binary(Map.get(death, "claim")) and
      is_integer(Map.get(death, "cycle_killed")) and
      is_binary(Map.get(death, "cause_of_death")) and
      is_binary(Map.get(death, "similarity_reason"))
  end
end
