defmodule Unshackled.Agents.Responses.CartographerSchema do
  @moduledoc """
  Ecto embedded schema for validating Cartographer agent responses.

  Validates that responses contain:
  - suggested_direction: vector or description of direction in embedding space (required)
  - target_region: description of underexplored region to explore (required)
  - exploration_rationale: why this direction is productive (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  embedded_schema do
    field(:suggested_direction, :string)
    field(:target_region, :string)
    field(:exploration_rationale, :string)
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and have sufficient length.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:suggested_direction, :target_region, :exploration_rationale])
    |> validate_required([:suggested_direction, :target_region, :exploration_rationale])
    |> validate_min_length(:suggested_direction, 10)
    |> validate_min_length(:target_region, 10)
    |> validate_min_length(:exploration_rationale, 20)
  end
end
