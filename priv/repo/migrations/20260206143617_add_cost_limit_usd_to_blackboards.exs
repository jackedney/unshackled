defmodule Unshackled.Repo.Migrations.AddCostLimitUsdToBlackboards do
  use Ecto.Migration

  def change do
    alter table(:blackboards) do
      add(:cost_limit_usd, :decimal, precision: 10, scale: 4)
    end
  end
end
