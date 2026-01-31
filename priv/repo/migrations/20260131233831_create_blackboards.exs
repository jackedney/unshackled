defmodule Unshackled.Repo.Migrations.CreateBlackboards do
  use Ecto.Migration

  def change do
    create table(:blackboards) do
      add :current_claim, :text, null: false
      add :support_strength, :float, null: false
      add :active_objection, :text
      add :analogy_of_record, :text
      add :frontier_pool, :json
      add :cemetery, :json
      add :cycle_count, :integer, default: 0
      add :embedding, :binary

      timestamps()
    end
  end
end
