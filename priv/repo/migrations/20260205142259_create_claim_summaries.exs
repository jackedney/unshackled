defmodule Unshackled.Repo.Migrations.CreateClaimSummaries do
  use Ecto.Migration

  def change do
    create table(:claim_summaries) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :cycle_number, :integer, null: false
      add :full_context_summary, :text
      add :evolution_narrative, :text
      add :addressed_objections, :json, default: "{}"
      add :remaining_gaps, :json, default: "{}"
      add :key_transitions, :json, default: "{}"

      timestamps()
    end

    create unique_index(:claim_summaries, [:blackboard_id, :cycle_number])
    create index(:claim_summaries, [:blackboard_id])
  end
end
