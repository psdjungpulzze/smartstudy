defmodule FunSheep.Repo.Migrations.AddClassifiedKindToUploadedMaterials do
  use Ecto.Migration

  @moduledoc """
  Phase 2 — material classifier.

  Root cause the classifier fixes: an answer-key image (`Biology Answers
  - 31.jpg` in the mid-April prod audit) was uploaded with
  `material_kind = :textbook` and fed to the regex extractor, producing
  462 garbage questions ("C 2. C 3. C 4. B 5." as a "question"). The
  extractor trusted the user-supplied `material_kind` without checking
  the OCR content. That trust is the bug.

  This migration keeps the user-supplied `material_kind` distinct from
  the AI-verified `classified_kind` so:
    * user intent is preserved (audit trail),
    * routing logic trusts the verified kind, not the label,
    * admin UI can flag mismatches (user said "textbook", classifier
      said "answer_key").

  `classified_kind` is a superset of `material_kind` because the
  classifier can detect categories users can't label:
    * `:question_bank`    — Q&A content (practice sets, past exams)
    * `:answer_key`       — answer tables only, no questions
    * `:knowledge_content` — textbook prose, study guides
    * `:mixed`            — pages of questions + answers interleaved
    * `:unusable`         — blank, duplicate, cover page, index only
    * `:uncertain`        — classifier low confidence; admin review
  """

  def change do
    alter table(:uploaded_materials) do
      add :classified_kind, :string
      add :kind_confidence, :float
      add :kind_classified_at, :utc_datetime
      add :kind_classification_notes, :text
    end

    # Partial index — only materials that have been classified. Admin
    # queries want "show me materials where user-kind disagrees with
    # classified-kind" which is cheap with this index.
    create index(:uploaded_materials, [:course_id, :classified_kind],
             where: "classified_kind IS NOT NULL",
             name: :uploaded_materials_course_id_classified_kind_index
           )
  end
end
