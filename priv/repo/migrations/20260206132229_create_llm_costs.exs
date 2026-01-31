defmodule Unshackled.Repo.Migrations.CreateLlmCosts do
  use Ecto.Migration

  def change do
    create table(:llm_costs) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :cycle_number, :integer, null: false
      add :agent_role, :string, null: false
      add :model_used, :string, null: false
      add :input_tokens, :integer, null: false
      add :output_tokens, :integer, null: false
      add :cost_usd, :float, null: false

      timestamps()
    end

    create index(:llm_costs, [:blackboard_id])
    create index(:llm_costs, [:blackboard_id, :cycle_number])
  end
end
