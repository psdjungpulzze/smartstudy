defmodule FunSheep.Repo.Migrations.AddPendingTocAndAcknowledgements do
  use Ecto.Migration

  def change do
    # A course holds at most one outstanding TOC proposal at a time. When a
    # proposal is pending approval, these columns point at the DiscoveredTOC
    # row that hasn't been applied yet, along with who uploaded the
    # materials that triggered it and when — the latter drives time-based
    # escalation (7d → active-majority, 14d → admin fallback).
    alter table(:courses) do
      add :pending_toc_id, references(:discovered_tocs, type: :binary_id, on_delete: :nilify_all)

      add :pending_toc_proposed_by_id,
          references(:user_roles, type: :binary_id, on_delete: :nilify_all)

      add :pending_toc_proposed_at, :utc_datetime
    end

    create index(:courses, [:pending_toc_id])
    create index(:courses, [:pending_toc_proposed_at])

    # Per-user, per-course dismissal of the "course was upgraded" banner.
    # Users who were on the course when a rebase landed see the notice
    # exactly once; the row records which discovered_toc they saw.
    create table(:user_course_toc_acknowledgements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_role_id,
          references(:user_roles, type: :binary_id, on_delete: :delete_all),
          null: false

      add :course_id,
          references(:courses, type: :binary_id, on_delete: :delete_all),
          null: false

      add :discovered_toc_id,
          references(:discovered_tocs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :dismissed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_course_toc_acknowledgements, [:user_role_id, :discovered_toc_id],
             name: :user_course_toc_acks_unique
           )
  end
end
