defmodule Unshackled.Blackboard.CemeteryEntry do
  @moduledoc """
  Ecto schema for the cemetery_entries table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "cemetery_entries" do
    field :claim, :string
    field :cause_of_death, :string
    field :final_support, :float
    field :cycle_killed, :integer

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(cemetery_entry, attrs) do
    cemetery_entry
    |> cast(attrs, [
      :blackboard_id,
      :claim,
      :cause_of_death,
      :final_support,
      :cycle_killed
    ])
    |> validate_required([
      :blackboard_id,
      :claim,
      :cause_of_death,
      :final_support,
      :cycle_killed
    ])
    |> foreign_key_constraint(:blackboard_id)
    |> assoc_constraint(:blackboard)
  end
end
