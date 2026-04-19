defmodule FunSheep.Repo.Migrations.CreateBillingTables do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :plan, :string, null: false, default: "free"
      add :status, :string, null: false, default: "active"
      add :billing_subscription_id, :string
      add :stripe_customer_id, :string
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :cancelled_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:user_role_id])
    create index(:subscriptions, [:billing_subscription_id])
    create index(:subscriptions, [:status])

    create table(:test_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id, references(:user_roles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :test_type, :string, null: false
      add :course_id, references(:courses, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:test_usages, [:user_role_id])
    create index(:test_usages, [:user_role_id, :inserted_at])
  end
end
