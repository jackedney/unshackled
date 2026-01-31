defmodule Unshackled.Embedding.TrajectoryPoint do
  @moduledoc """
  Ecto schema for trajectory_points table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          cycle_number: integer() | nil,
          embedding_vector: binary() | nil,
          claim_text: String.t() | nil,
          support_strength: float() | nil,
          id: pos_integer() | nil,
          blackboard_id: pos_integer() | nil,
          blackboard: term() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "trajectory_points" do
    field :cycle_number, :integer
    field :embedding_vector, :binary
    field :claim_text, :string
    field :support_strength, :float

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t() | t(), map()) :: Ecto.Changeset.t()
  def changeset(trajectory_point, attrs) do
    trajectory_point
    |> cast(attrs, [
      :blackboard_id,
      :cycle_number,
      :embedding_vector,
      :claim_text,
      :support_strength
    ])
    |> validate_required([
      :blackboard_id,
      :cycle_number,
      :embedding_vector,
      :claim_text,
      :support_strength
    ])
    |> validate_number(:cycle_number, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:blackboard_id)
    |> assoc_constraint(:blackboard)
  end
end
