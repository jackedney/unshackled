defmodule Unshackled.Evolution.ClaimTransition do
  @moduledoc """
  Ecto schema for the claim_transitions table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :blackboard_id,
             :from_cycle,
             :to_cycle,
             :previous_claim,
             :new_claim,
             :trigger_agent,
             :trigger_contribution_id,
             :change_type,
             :diff_additions,
             :diff_removals,
             :inserted_at
           ]}

  @valid_change_types ~w[
    refinement
    pivot
    expansion
    contraction
  ]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          blackboard_id: pos_integer() | nil,
          blackboard: term() | nil,
          from_cycle: integer() | nil,
          to_cycle: integer() | nil,
          previous_claim: String.t() | nil,
          new_claim: String.t() | nil,
          trigger_agent: String.t() | nil,
          trigger_contribution_id: integer() | nil,
          change_type: String.t() | nil,
          diff_additions: map() | nil,
          diff_removals: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "claim_transitions" do
    field :from_cycle, :integer
    field :to_cycle, :integer
    field :previous_claim, :string
    field :new_claim, :string
    field :trigger_agent, :string
    field :trigger_contribution_id, :integer
    field :change_type, :string
    field :diff_additions, :map, default: %{}
    field :diff_removals, :map, default: %{}

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps(updated_at: false)
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(claim_transition, attrs) do
    claim_transition
    |> cast(attrs, [
      :blackboard_id,
      :from_cycle,
      :to_cycle,
      :previous_claim,
      :new_claim,
      :trigger_agent,
      :trigger_contribution_id,
      :change_type,
      :diff_additions,
      :diff_removals
    ])
    |> validate_required([
      :blackboard_id,
      :from_cycle,
      :to_cycle,
      :previous_claim,
      :new_claim,
      :trigger_agent,
      :change_type
    ])
    |> validate_inclusion(:change_type, @valid_change_types,
      message: "must be one of: #{Enum.join(@valid_change_types, ", ")}"
    )
    |> validate_number(:from_cycle, greater_than_or_equal_to: 0)
    |> validate_number(:to_cycle, greater_than_or_equal_to: 0)
    |> validate_cycle_order()
    |> foreign_key_constraint(:blackboard_id)
    |> unique_constraint([:blackboard_id, :to_cycle])
  end

  defp validate_cycle_order(changeset) do
    from_cycle = get_change(changeset, :from_cycle)
    to_cycle = get_change(changeset, :to_cycle)

    case {from_cycle, to_cycle} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {f, t} when is_integer(f) and is_integer(t) and t <= f ->
        add_error(changeset, :to_cycle, "must be greater than from_cycle")

      _ ->
        changeset
    end
  end
end
