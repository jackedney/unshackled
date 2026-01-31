defmodule Unshackled.Repo.Migrations.CreateCemeteryEntries do
  use Ecto.Migration

  def change do
    create table(:cemetery_entries) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :claim, :text, null: false
      add :cause_of_death, :text, null: false
      add :final_support, :float, null: false
      add :cycle_killed, :integer, null: false

      timestamps()
    end

    create index(:cemetery_entries, [:blackboard_id, :cycle_killed])
  end
end
