defmodule Unshackled.Agents.Responses.ValidationHelpers do
  @moduledoc """
  Shared validation helpers for response schemas.
  """

  import Ecto.Changeset

  @doc """
  Validates that a string field has minimum length.
  """
  @spec validate_min_length(Ecto.Changeset.t(), atom(), non_neg_integer()) :: Ecto.Changeset.t()
  def validate_min_length(changeset, field, min_length) do
    value = get_change(changeset, field)

    if value && is_binary(value) do
      if String.length(String.trim(value)) < min_length do
        add_error(changeset, field, "must be at least #{min_length} characters")
      else
        changeset
      end
    else
      changeset
    end
  end
end
