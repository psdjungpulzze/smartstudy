defmodule FunSheep.Repo.Migrations.BackfillCourseSchoolIdFromCreator do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE courses
    SET school_id = ur.school_id
    FROM user_roles ur
    WHERE courses.created_by_id = ur.id
      AND courses.school_id IS NULL
      AND ur.school_id IS NOT NULL
    """)
  end

  def down do
    # Irreversible — cannot know which courses had school_id set before
    :ok
  end
end
