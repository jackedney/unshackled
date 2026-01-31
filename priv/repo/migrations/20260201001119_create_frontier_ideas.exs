defmodule Unshackled.Repo.Migrations.CreateFrontierIdeas do
  use Ecto.Migration

  def change do
    create table(:frontier_ideas) do
      add :blackboard_id, references(:blackboards, on_delete: :delete_all), null: false
      add :idea_text, :text, null: false
      add :sponsor_count, :integer, default: 0, null: false
      add :cycles_alive, :integer, default: 0, null: false
      add :activated, :boolean, default: false, null: false

      timestamps()
    end

    create index(:frontier_ideas, [:blackboard_id, :activated])
    create index(:frontier_ideas, [:blackboard_id, :sponsor_count])
  end
end
