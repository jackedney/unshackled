defmodule Unshackled.Repo.Migrations.CreateBlackboardSnapshots do
  use Ecto.Migration

  def change do
    create table(:blackboard_snapshots) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :cycle_number, :integer, null: false
      add :state_json, :json
      add :embedding_vector, :binary

      timestamps()
    end

    create index(:blackboard_snapshots, [:blackboard_id, :cycle_number])
  end
end
