defmodule Unshackled.Evolution.ClaimSummary do
  @moduledoc """
  Ecto schema for the claim_summaries table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          blackboard_id: pos_integer() | nil,
          blackboard: term() | nil,
          cycle_number: integer() | nil,
          full_context_summary: String.t() | nil,
          evolution_narrative: String.t() | nil,
          addressed_objections: map() | nil,
          remaining_gaps: map() | nil,
          key_transitions: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "claim_summaries" do
    field :cycle_number, :integer
    field :full_context_summary, :string
    field :evolution_narrative, :string
    field :addressed_objections, :map, default: %{}
    field :remaining_gaps, :map, default: %{}
    field :key_transitions, :map, default: %{}

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(claim_summary, attrs) do
    claim_summary
    |> cast(attrs, [
      :blackboard_id,
      :cycle_number,
      :full_context_summary,
      :evolution_narrative,
      :addressed_objections,
      :remaining_gaps,
      :key_transitions
    ])
    |> validate_required([
      :blackboard_id,
      :cycle_number
    ])
    |> validate_number(:cycle_number, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:blackboard_id)
    |> unique_constraint([:blackboard_id, :cycle_number])
  end
end
