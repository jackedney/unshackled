defmodule Unshackled.Blackboard.BlackboardSnapshot do
  @moduledoc """
  Ecto schema for the blackboard_snapshots table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "blackboard_snapshots" do
    field :cycle_number, :integer
    field :state_json, :map
    field :embedding_vector, :binary

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(blackboard_snapshot, attrs) do
    blackboard_snapshot
    |> cast(attrs, [
      :blackboard_id,
      :cycle_number,
      :state_json,
      :embedding_vector
    ])
    |> validate_required([:blackboard_id, :cycle_number])
    |> foreign_key_constraint(:blackboard_id)
    |> assoc_constraint(:blackboard)
  end
end
