defmodule FunSheep.Repo.Migrations.AddPayerToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      # §3.1, §7.2 — payer-vs-beneficiary split. user_role_id remains the
      # beneficiary (student). paid_by_user_role_id is the payer (parent or
      # student themselves). Teachers never appear here.
      add :paid_by_user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      # Links a paid subscription back to the practice_request that produced
      # it (Flow A). Null for self-purchase or parent upfront purchase (Flow B).
      add :origin_practice_request_id,
          references(:practice_requests, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:subscriptions, [:paid_by_user_role_id])
  end
end
