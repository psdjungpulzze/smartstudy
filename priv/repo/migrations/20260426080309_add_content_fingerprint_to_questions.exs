defmodule FunSheep.Repo.Migrations.AddContentFingerprintToQuestions do
  use Ecto.Migration

  def change do
    alter table(:questions) do
      add :content_fingerprint, :string
    end

    # Partial unique index: only enforce deduplication for web-scraped questions.
    # AI-generated questions intentionally allow the same content in different courses.
    create unique_index(:questions, [:course_id, :content_fingerprint],
             where: "content_fingerprint IS NOT NULL AND source_type = 'web_scraped'",
             name: :questions_course_id_content_fingerprint_index
           )
  end
end
