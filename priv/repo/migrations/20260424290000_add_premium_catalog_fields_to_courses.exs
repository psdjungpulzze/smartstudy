defmodule FunSheep.Repo.Migrations.AddPremiumCatalogFieldsToCourses do
  use Ecto.Migration

  def change do
    alter table(:courses) do
      add :access_level, :string, default: "public", null: false
      add :is_premium_catalog, :boolean, default: false, null: false
      # 'sat', 'act', 'ap', 'ib', 'hsc', 'clt', 'lsat', 'bar', 'gmat', 'mcat', 'gre'
      add :catalog_test_type, :string
      # 'mathematics', 'biology', 'english_language', etc.
      add :catalog_subject, :string
      # 'hl', 'sl', 'ab', 'bc', '1', '2', etc.
      add :catalog_level, :string
      add :published_at, :utc_datetime
      add :published_by_id, references(:user_roles, type: :binary_id, on_delete: :nilify_all)
      add :sample_question_count, :integer, default: 10, null: false
    end

    create index(:courses, [:is_premium_catalog])
    create index(:courses, [:catalog_test_type])
    create index(:courses, [:access_level])
  end
end
