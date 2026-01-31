defmodule Unshackled.Blackboard.BlackboardRecord do
  @moduledoc """
  Ecto schema for the blackboards table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Unshackled.Repo

  schema "blackboards" do
    field :current_claim, :string
    field :support_strength, :float
    field :active_objection, :string
    field :analogy_of_record, :string
    field :frontier_pool, :map
    field :cemetery, :map
    field :cycle_count, :integer, default: 0
    field :embedding, :binary
    field :translator_frameworks_used, {:array, :string}, default: []
    field :cost_limit_usd, :decimal

    timestamps()
  end

  @spec changeset(Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(blackboard_record, attrs) do
    blackboard_record
    |> cast(attrs, [
      :current_claim,
      :support_strength,
      :active_objection,
      :analogy_of_record,
      :frontier_pool,
      :cemetery,
      :cycle_count,
      :embedding,
      :translator_frameworks_used,
      :cost_limit_usd
    ])
    |> validate_required([:current_claim, :support_strength])
    |> validate_number(:support_strength,
      greater_than_or_equal_to: 0.2,
      less_than_or_equal_to: 0.9
    )
  end

  @doc """
  Deletes a blackboard record and all associated data.

  All related tables have `on_delete: :delete_all` configured,
  so this will cascade delete all agent_contributions, blackboard_snapshots,
  cemetery_entries, frontier_ideas, trajectory_points, claim_transitions,
  claim_summaries, and llm_costs.

  Returns {:ok, blackboard} on success.
  Returns {:error, changeset} on failure.
  """
  @spec delete(%__MODULE__{}) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = blackboard) do
    Repo.delete(blackboard)
  end

  @doc """
  Deletes all blackboard records and associated data.

  Returns the number of deleted records.
  """
  @spec delete_all() :: {non_neg_integer(), nil}
  def delete_all do
    Repo.delete_all(__MODULE__)
  end
end
