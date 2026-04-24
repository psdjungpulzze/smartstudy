defmodule FunSheep.Repo.Migrations.MergeSeedSchoolsIntoNces do
  use Ecto.Migration

  @doc """
  Merges seed-created school records (source IS NULL) into their NCES CCD
  counterparts where an unambiguous match exists.

  Seed schools were inserted by priv/repo/seeds.exs before the ingestion
  pipeline existed. They only have {name, district_id} set — no source,
  state_id, country_id, level, or type. After NCES ingestion the same real
  schools now exist as proper records with full geo data and source="nces_ccd".

  Matching criteria (all must hold):
    1. Same US state  — seed school's district.state_id = nces school.state_id
    2. Name equivalence — exact match OR one name is the other plus a common
       school-type suffix (" School", " High School", " Middle School",
       " Elementary School").
    3. Unambiguous — exactly one NCES school matches; skipped otherwise.

  For every matched pair:
    • user_roles, courses, questions with school_id = seed_id → nces_id
    • seed school row deleted

  Non-US seed schools (Korea, Canada) have no NCES counterpart and are left
  untouched.
  """
  def up do
    execute("""
    DO $$
    DECLARE
      r           RECORD;
      n_roles     INT;
      n_courses   INT;
      n_questions INT;
      n_merged    INT := 0;
      n_skipped   INT := 0;
    BEGIN
      -- ── Identify seed → NCES pairs ──────────────────────────────────────────
      --
      -- Seed schools have source IS NULL and only district_id (no state_id).
      -- We reach their state via districts.state_id.
      -- NCES schools carry state_id directly.
      -- We match on state + name equivalence (exact or suffix-stripped).
      --
      FOR r IN
        WITH seed_schools AS (
          SELECT s.id, s.name, d.state_id
          FROM   schools    s
          JOIN   districts  d ON d.id = s.district_id
          WHERE  s.source IS NULL
          AND    d.state_id IS NOT NULL
        ),
        nces_schools AS (
          SELECT id, name, state_id
          FROM   schools
          WHERE  source     = 'nces_ccd'
          AND    state_id IS NOT NULL
        ),
        candidates AS (
          SELECT
            seed.id        AS seed_id,
            seed.name      AS seed_name,
            nces.id        AS nces_id,
            nces.name      AS nces_name,
            COUNT(*)  OVER (PARTITION BY seed.id) AS match_count
          FROM seed_schools seed
          JOIN nces_schools nces ON nces.state_id = seed.state_id
          WHERE
            -- exact (case-insensitive)
            lower(nces.name) = lower(seed.name)
            -- seed name = nces name + common suffix
            OR lower(seed.name) = lower(nces.name) || ' school'
            OR lower(seed.name) = lower(nces.name) || ' high school'
            OR lower(seed.name) = lower(nces.name) || ' middle school'
            OR lower(seed.name) = lower(nces.name) || ' elementary school'
            -- nces name = seed name + common suffix
            OR lower(nces.name) = lower(seed.name) || ' school'
            OR lower(nces.name) = lower(seed.name) || ' high school'
            OR lower(nces.name) = lower(seed.name) || ' middle school'
            OR lower(nces.name) = lower(seed.name) || ' elementary school'
        )
        SELECT seed_id, seed_name, nces_id, nces_name, match_count
        FROM   candidates
        ORDER  BY seed_name
      LOOP
        IF r.match_count > 1 THEN
          RAISE WARNING 'SKIP (ambiguous) seed "%" matched % NCES schools — manual review needed',
            r.seed_name, r.match_count;
          n_skipped := n_skipped + 1;
          CONTINUE;
        END IF;

        RAISE NOTICE 'MERGE seed "%" (%) → NCES "%" (%)',
          r.seed_name, r.seed_id, r.nces_name, r.nces_id;

        -- Reassign user_roles
        UPDATE user_roles
        SET    school_id = r.nces_id
        WHERE  school_id = r.seed_id;
        GET DIAGNOSTICS n_roles = ROW_COUNT;

        -- Reassign courses
        UPDATE courses
        SET    school_id = r.nces_id
        WHERE  school_id = r.seed_id;
        GET DIAGNOSTICS n_courses = ROW_COUNT;

        -- Reassign questions
        UPDATE questions
        SET    school_id = r.nces_id
        WHERE  school_id = r.seed_id;
        GET DIAGNOSTICS n_questions = ROW_COUNT;

        RAISE NOTICE '  moved % user_roles, % courses, % questions',
          n_roles, n_courses, n_questions;

        DELETE FROM schools WHERE id = r.seed_id;

        n_merged := n_merged + 1;
      END LOOP;

      RAISE NOTICE '=== Done: % seed schools merged, % skipped (ambiguous) ===',
        n_merged, n_skipped;
    END $$;
    """)
  end

  def down do
    raise Ecto.MigrationError,
      message: """
      MergeSeedSchoolsIntoNces is irreversible.
      The deleted seed school rows cannot be recovered automatically.
      Restore from a pre-migration database snapshot if rollback is needed.
      """
  end
end
