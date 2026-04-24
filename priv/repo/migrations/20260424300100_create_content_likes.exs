defmodule FunSheep.Repo.Migrations.CreateContentLikes do
  use Ecto.Migration

  def change do
    create table(:content_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :course_id,
          references(:courses, type: :binary_id, on_delete: :delete_all),
          null: true

      add :reaction, :string, null: false
      add :context, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:content_likes, [:user_role_id, :course_id],
             where: "course_id IS NOT NULL",
             name: :content_likes_user_course_unique
           )

    create index(:content_likes, [:course_id])
    create index(:content_likes, [:user_role_id])
  end
end
