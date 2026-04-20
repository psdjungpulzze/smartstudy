defmodule FunSheep.Repo.Migrations.DedupeStatesWithoutIso do
  @moduledoc """
  Before `seeds_geo_iso.exs` existed, states were seeded with display names
  like "Seoul (서울)" and no `iso_code`. The new seed adds canonical rows
  with ISO codes (e.g. "Seoul" / "KR-11"), which produced duplicates.

  This migration consolidates the duplicates: for every legacy state
  without an `iso_code`, if a canonical ISO row exists for the same
  country with the same name prefix, re-point every referencing district,
  school, and university to the canonical row and delete the legacy row.
  """

  use Ecto.Migration

  def up do
    execute("""
    WITH canonical AS (
      SELECT DISTINCT ON (country_id, split_part(name, ' (', 1))
        id AS canonical_id,
        country_id,
        split_part(name, ' (', 1) AS short_name
      FROM states
      WHERE iso_code IS NOT NULL
      ORDER BY country_id, split_part(name, ' (', 1), inserted_at ASC
    ),
    dups AS (
      SELECT s.id AS legacy_id, c.canonical_id
      FROM states s
      JOIN canonical c
        ON s.country_id = c.country_id
       AND split_part(s.name, ' (', 1) = c.short_name
      WHERE s.iso_code IS NULL
        AND s.id <> c.canonical_id
    )
    UPDATE districts d
       SET state_id = dups.canonical_id
      FROM dups
     WHERE d.state_id = dups.legacy_id;
    """)

    execute("""
    WITH canonical AS (
      SELECT DISTINCT ON (country_id, split_part(name, ' (', 1))
        id AS canonical_id,
        country_id,
        split_part(name, ' (', 1) AS short_name
      FROM states
      WHERE iso_code IS NOT NULL
      ORDER BY country_id, split_part(name, ' (', 1), inserted_at ASC
    ),
    dups AS (
      SELECT s.id AS legacy_id, c.canonical_id
      FROM states s
      JOIN canonical c
        ON s.country_id = c.country_id
       AND split_part(s.name, ' (', 1) = c.short_name
      WHERE s.iso_code IS NULL
        AND s.id <> c.canonical_id
    )
    UPDATE schools sc
       SET state_id = dups.canonical_id
      FROM dups
     WHERE sc.state_id = dups.legacy_id;
    """)

    execute("""
    WITH canonical AS (
      SELECT DISTINCT ON (country_id, split_part(name, ' (', 1))
        id AS canonical_id,
        country_id,
        split_part(name, ' (', 1) AS short_name
      FROM states
      WHERE iso_code IS NOT NULL
      ORDER BY country_id, split_part(name, ' (', 1), inserted_at ASC
    ),
    dups AS (
      SELECT s.id AS legacy_id, c.canonical_id
      FROM states s
      JOIN canonical c
        ON s.country_id = c.country_id
       AND split_part(s.name, ' (', 1) = c.short_name
      WHERE s.iso_code IS NULL
        AND s.id <> c.canonical_id
    )
    UPDATE universities u
       SET state_id = dups.canonical_id
      FROM dups
     WHERE u.state_id = dups.legacy_id;
    """)

    execute("""
    WITH canonical AS (
      SELECT DISTINCT ON (country_id, split_part(name, ' (', 1))
        id AS canonical_id,
        country_id,
        split_part(name, ' (', 1) AS short_name
      FROM states
      WHERE iso_code IS NOT NULL
      ORDER BY country_id, split_part(name, ' (', 1), inserted_at ASC
    )
    DELETE FROM states s
      USING canonical c
     WHERE s.country_id = c.country_id
       AND split_part(s.name, ' (', 1) = c.short_name
       AND s.iso_code IS NULL
       AND s.id <> c.canonical_id;
    """)

    # Second pass: legacy "Foo (원문)" rows that don't prefix-match a canonical
    # row (e.g. old "Gyeongnam (경남)" vs. new canonical "South Gyeongsang")
    # but have no children are safe to drop outright. Rows with children are
    # left alone — operator can re-point them manually.
    execute("""
    DELETE FROM states s
     WHERE s.iso_code IS NULL
       AND s.name LIKE '%(%'
       AND NOT EXISTS (SELECT 1 FROM districts WHERE state_id = s.id)
       AND NOT EXISTS (SELECT 1 FROM schools WHERE state_id = s.id)
       AND NOT EXISTS (SELECT 1 FROM universities WHERE state_id = s.id);
    """)
  end

  def down, do: :ok
end
