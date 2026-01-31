defmodule Unshackled.Agents.Responses.ReducerSchema do
  @moduledoc """
  Ecto embedded schema for validating Reducer agent responses.

  Validates that responses contain:
  - essential_claim: distilled core proposition (required)
  - removed_elements: list of elements removed during reduction (required)
  - preserved_elements: list of elements preserved in the reduction (required)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Unshackled.Agents.Responses.ValidationHelpers

  embedded_schema do
    field(:essential_claim, :string)
    field(:removed_elements, {:array, :string})
    field(:preserved_elements, {:array, :string})
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and lists are arrays.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:essential_claim, :removed_elements, :preserved_elements])
    |> validate_required([:essential_claim, :removed_elements, :preserved_elements])
    |> validate_min_length(:essential_claim, 10)
    |> validate_list(:removed_elements)
    |> validate_list(:preserved_elements)
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
