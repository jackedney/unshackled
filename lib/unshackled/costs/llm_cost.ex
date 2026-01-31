defmodule Unshackled.Costs.LLMCost do
  @moduledoc """
  Ecto schema for the llm_costs table.
  Stores token usage and cost data for LLM API calls.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "llm_costs" do
    field :blackboard_id, :integer
    field :cycle_number, :integer
    field :agent_role, :string
    field :model_used, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :cost_usd, :float

    belongs_to :blackboard_record, Unshackled.Blackboard.BlackboardRecord

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(llm_cost, attrs) do
    llm_cost
    |> cast(attrs, [
      :blackboard_id,
      :cycle_number,
      :agent_role,
      :model_used,
      :input_tokens,
      :output_tokens,
      :cost_usd
    ])
    |> validate_required([
      :blackboard_id,
      :cycle_number,
      :agent_role,
      :model_used
    ])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cost_usd, greater_than_or_equal_to: 0.0)
    |> foreign_key_constraint(:blackboard_id)
  end
end
