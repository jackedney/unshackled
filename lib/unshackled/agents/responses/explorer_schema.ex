defmodule Unshackled.Agents.Responses.ExplorerSchema do
  @moduledoc """
  Ecto embedded schema for validating Explorer agent responses.

  Validates that responses contain:
  - new_claim: the extended claim (required)
  - inference_type: the type of inference (required, must be deductive|inductive|abductive)
  - reasoning: explanation of the inference (optional)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @valid_inference_types ~w(deductive inductive abductive)

  embedded_schema do
    field(:new_claim, :string)
    field(:inference_type, :string)
    field(:reasoning, :string, default: "")
  end

  @doc """
  Creates a changeset from a map of attributes.

  Validates that required fields are present and that inference_type is one of the allowed values.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:new_claim, :inference_type, :reasoning])
    |> validate_required([:new_claim, :inference_type])
    |> validate_inclusion(:inference_type, @valid_inference_types)
  end
end
