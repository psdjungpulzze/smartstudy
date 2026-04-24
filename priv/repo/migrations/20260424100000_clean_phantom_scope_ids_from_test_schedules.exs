defmodule FunSheep.Repo.Migrations.CleanPhantomScopeIdsFromTestSchedules do
  use Ecto.Migration

  @doc """
  Removes chapter_ids and section_ids from test_schedule.scope that no longer
  exist in the chapters/sections tables. These stale UUIDs arise when a course
  is restructured after a schedule was created and cause silent 100%-readiness
  blocks (unattemptable phantom sections counted in map_size).
  """
  def up do
    execute("""
    UPDATE test_schedules
    SET scope = jsonb_set(
      jsonb_set(
        scope,
        '{chapter_ids}',
        (
          SELECT jsonb_agg(cid)
          FROM jsonb_array_elements_text(scope->'chapter_ids') AS cid
          WHERE EXISTS (SELECT 1 FROM chapters WHERE id = cid::uuid)
        )
      ),
      '{section_ids}',
      COALESCE(
        (
          SELECT jsonb_agg(sid)
          FROM jsonb_array_elements_text(scope->'section_ids') AS sid
          WHERE EXISTS (SELECT 1 FROM sections WHERE id = sid::uuid)
        ),
        '[]'::jsonb
      )
    )
    WHERE
      scope ? 'chapter_ids'
      AND (
        EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text(scope->'chapter_ids') AS cid
          WHERE NOT EXISTS (SELECT 1 FROM chapters WHERE id = cid::uuid)
        )
        OR EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text(scope->'section_ids') AS sid
          WHERE NOT EXISTS (SELECT 1 FROM sections WHERE id = sid::uuid)
        )
      )
    """)
  end

  def down do
    # Data migration — cannot be reversed without a backup.
    :ok
  end
end
