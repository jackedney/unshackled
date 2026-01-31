defmodule Unshackled.Repo.Migrations.AddTranslatorFrameworksUsedToBlackboards do
  use Ecto.Migration

  def change do
    alter table(:blackboards) do
      add(:translator_frameworks_used, {:array, :string}, default: [])
    end
  end
end
