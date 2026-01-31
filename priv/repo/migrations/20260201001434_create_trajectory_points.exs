defmodule Unshackled.Repo.Migrations.CreateTrajectoryPoints do
  use Ecto.Migration

  def change do
    create table(:trajectory_points) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :cycle_number, :integer, null: false
      add :embedding_vector, :binary, null: false
      add :claim_text, :text, null: false
      add :support_strength, :float, null: false

      timestamps()
    end

    create index(:trajectory_points, [:blackboard_id, :cycle_number])
  end
end
