defmodule Unshackled.Agents.Responses.PerturberSchema do
  @moduledoc """
  Ecto embedded schema for validating Perturber agent responses.

  Validates that responses contain:
  - pivot_claim: new claim derived from frontier idea (required)
  - connection_to_previous: explanation of how this pivot relates to previous debate (required)
  - pivot_rationale: why this pivot is strategically valuable (required)
  - activated: boolean indicating if perturber was activated (optional, default false)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  embedded_schema do
    field(:pivot_claim, :string)
    field(:connection_to_previous, :string)
    field(:pivot_rationale, :string)
    field(:activated, :boolean, default: false)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and have sufficient length.
  When activated is false, pivot fields can be nil.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:pivot_claim, :connection_to_previous, :pivot_rationale, :activated])
    |> validate_based_on_activation()
  end

  @spec validate_based_on_activation(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_based_on_activation(changeset) do
    activated = get_change(changeset, :activated)

    if activated == false do
      # Skip validation for non-activated responses
      changeset
    else
      # Validate all fields are present when activated
      changeset
      |> put_change(:activated, true)
      |> validate_required([:pivot_claim, :connection_to_previous, :pivot_rationale])
      |> validate_min_length(:pivot_claim, 10)
      |> validate_min_length(:connection_to_previous, 15)
      |> validate_min_length(:pivot_rationale, 15)
    end
  end
end
