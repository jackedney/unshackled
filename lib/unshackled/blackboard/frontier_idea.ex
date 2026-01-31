defmodule Unshackled.Blackboard.FrontierIdea do
  @moduledoc """
  Ecto schema for the frontier_ideas table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "frontier_ideas" do
    field :idea_text, :string
    field :sponsor_count, :integer, default: 0
    field :cycles_alive, :integer, default: 0
    field :activated, :boolean, default: false

    belongs_to :blackboard, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(frontier_idea, attrs) do
    frontier_idea
    |> cast(attrs, [
      :blackboard_id,
      :idea_text,
      :sponsor_count,
      :cycles_alive,
      :activated
    ])
    |> validate_required([
      :blackboard_id,
      :idea_text,
      :sponsor_count,
      :cycles_alive,
      :activated
    ])
    |> validate_number(:sponsor_count, greater_than_or_equal_to: 0)
    |> validate_number(:cycles_alive, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:blackboard_id)
    |> assoc_constraint(:blackboard)
  end

  @doc """
  Check if a frontier idea is eligible for activation.
  An idea is eligible when sponsor_count >= 2 and not activated.
  """
  @spec eligible_for_activation?(Ecto.Schema.t()) :: boolean()
  def eligible_for_activation?(%__MODULE__{sponsor_count: count, activated: activated})
      when is_integer(count) and is_boolean(activated) do
    count >= 2 and not activated
  end

  def eligible_for_activation?(_), do: false
end
