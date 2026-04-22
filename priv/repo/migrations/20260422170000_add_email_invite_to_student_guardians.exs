defmodule FunSheep.Repo.Migrations.AddEmailInviteToStudentGuardians do
  use Ecto.Migration

  def change do
    alter table(:student_guardians) do
      modify :guardian_id, :binary_id, null: true, from: {:binary_id, null: false}
      add :invited_email, :string
      add :invite_token, :string
      add :invite_token_expires_at, :utc_datetime
    end

    create unique_index(:student_guardians, [:invite_token],
             where: "invite_token IS NOT NULL",
             name: :student_guardians_invite_token_index
           )

    create index(:student_guardians, [:invited_email])

    create constraint(:student_guardians, :guardian_or_email_present,
             check: "guardian_id IS NOT NULL OR invited_email IS NOT NULL"
           )
  end
end
