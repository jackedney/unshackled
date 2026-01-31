defmodule Unshackled.Repo.Migrations.CreateClaimTransitions do
  use Ecto.Migration

  def change do
    create table(:claim_transitions) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :from_cycle, :integer, null: false
      add :to_cycle, :integer, null: false
      add :previous_claim, :text, null: false
      add :new_claim, :text, null: false
      add :trigger_agent, :string, null: false
      add :trigger_contribution_id, :bigint
      add :change_type, :string, null: false
      add :diff_additions, :json, default: "{}"
      add :diff_removals, :json, default: "{}"

      timestamps(updated_at: false)
    end

    create unique_index(:claim_transitions, [:blackboard_id, :to_cycle])
    create index(:claim_transitions, [:blackboard_id])
  end
end
