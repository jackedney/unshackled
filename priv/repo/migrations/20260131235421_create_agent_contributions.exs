defmodule Unshackled.Repo.Migrations.CreateAgentContributions do
  use Ecto.Migration

  def change do
    create table(:agent_contributions) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :cycle_number, :integer, null: false
      add :agent_role, :string, null: false
      add :model_used, :string, null: false
      add :input_prompt, :text, null: false
      add :output_text, :text, null: false
      add :accepted, :boolean, default: false, null: false
      add :support_delta, :float

      timestamps()
    end

    create index(:agent_contributions, [:blackboard_id, :cycle_number, :agent_role])
  end
end
