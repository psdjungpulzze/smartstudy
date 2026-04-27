# Source Registry seed data — curated Tier 1–2 sources for the top 10 test types.
#
# Run with:  mix run priv/repo/seeds/source_registry.exs
# Idempotent: uses INSERT ... ON CONFLICT DO NOTHING via create_discovered_source_if_new.

import Ecto.Query
alias FunSheep.{Repo}
alias FunSheep.Discovery.SourceRegistryEntry

entries = [
  # ── SAT ──────────────────────────────────────────────────────────────────
  %{
    test_type: "sat",
    catalog_subject: nil,
    url_or_pattern: "https://satsuite.collegeboard.org/practice/practice-tests",
    domain: "collegeboard.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 50,
    notes: "Official SAT practice tests from College Board"
  },
  %{
    test_type: "sat",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/test-prep/sat",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 30,
    notes: "Official partnership with College Board"
  },
  %{
    test_type: "sat",
    catalog_subject: nil,
    url_or_pattern: "https://www.collegeboard.org/sat/practice",
    domain: "collegeboard.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 40,
    notes: "College Board main practice hub"
  },
  %{
    test_type: "sat",
    catalog_subject: "mathematics",
    url_or_pattern: "https://www.khanacademy.org/test-prep/sat/sat-math-practice",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 25
  },
  %{
    test_type: "sat",
    catalog_subject: nil,
    url_or_pattern: "https://www.prepscholar.com/sat/s/questions",
    domain: "prepscholar.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 20
  },

  # ── ACT ──────────────────────────────────────────────────────────────────
  %{
    test_type: "act",
    catalog_subject: nil,
    url_or_pattern: "https://www.act.org/content/act/en/products-and-services/the-act/test-preparation/free-act-test-prep.html",
    domain: "act.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 40,
    notes: "Official ACT free practice materials"
  },
  %{
    test_type: "act",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/test-prep/act",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 25
  },
  %{
    test_type: "act",
    catalog_subject: nil,
    url_or_pattern: "https://www.prepscholar.com/act/s/questions",
    domain: "prepscholar.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 20
  },

  # ── AP Calculus AB ────────────────────────────────────────────────────────
  %{
    test_type: "ap_calculus_ab",
    catalog_subject: nil,
    url_or_pattern: "https://apcentral.collegeboard.org/courses/ap-calculus-ab/exam/past-exam-questions",
    domain: "collegeboard.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 45,
    notes: "Official AP past free-response questions"
  },
  %{
    test_type: "ap_calculus_ab",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/math/ap-calculus-ab",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 20
  },
  %{
    test_type: "ap_calculus_ab",
    catalog_subject: nil,
    url_or_pattern: "https://albert.io/ap-calculus-ab",
    domain: "albert.io",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 30
  },

  # ── AP Biology ──────────────────────────────────────────────────────────
  %{
    test_type: "ap_biology",
    catalog_subject: nil,
    url_or_pattern: "https://apcentral.collegeboard.org/courses/ap-biology/exam/past-exam-questions",
    domain: "collegeboard.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 40
  },
  %{
    test_type: "ap_biology",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/science/ap-biology",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 18
  },
  %{
    test_type: "ap_biology",
    catalog_subject: nil,
    url_or_pattern: "https://albert.io/ap-biology",
    domain: "albert.io",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 28
  },

  # ── AP Chemistry ────────────────────────────────────────────────────────
  %{
    test_type: "ap_chemistry",
    catalog_subject: nil,
    url_or_pattern: "https://apcentral.collegeboard.org/courses/ap-chemistry/exam/past-exam-questions",
    domain: "collegeboard.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 35
  },
  %{
    test_type: "ap_chemistry",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/science/ap-chemistry-beta",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 15
  },
  %{
    test_type: "ap_chemistry",
    catalog_subject: nil,
    url_or_pattern: "https://albert.io/ap-chemistry",
    domain: "albert.io",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 25
  },

  # ── AP US History ────────────────────────────────────────────────────────
  %{
    test_type: "ap_us_history",
    catalog_subject: nil,
    url_or_pattern: "https://apcentral.collegeboard.org/courses/ap-united-states-history/exam/past-exam-questions",
    domain: "collegeboard.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 50
  },
  %{
    test_type: "ap_us_history",
    catalog_subject: nil,
    url_or_pattern: "https://albert.io/ap-us-history",
    domain: "albert.io",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 30
  },
  %{
    test_type: "ap_us_history",
    catalog_subject: nil,
    url_or_pattern: "https://www.varsitytutors.com/ap_us_history-practice-tests",
    domain: "varsitytutors.com",
    source_type: "practice_test",
    tier: 2,
    avg_questions_per_page: 20
  },

  # ── GRE ─────────────────────────────────────────────────────────────────
  %{
    test_type: "gre",
    catalog_subject: nil,
    url_or_pattern: "https://www.ets.org/gre/test-takers/general-test/prepare/powerprep.html",
    domain: "ets.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 40,
    notes: "Official ETS POWERPREP practice"
  },
  %{
    test_type: "gre",
    catalog_subject: nil,
    url_or_pattern: "https://www.magoosh.com/gre/gre-practice-questions",
    domain: "magoosh.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 20
  },
  %{
    test_type: "gre",
    catalog_subject: nil,
    url_or_pattern: "https://www.prepscholar.com/gre/s/questions",
    domain: "prepscholar.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 15
  },

  # ── LSAT ────────────────────────────────────────────────────────────────
  %{
    test_type: "lsat",
    catalog_subject: nil,
    url_or_pattern: "https://www.lsac.org/lsat/prep",
    domain: "lsac.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 25,
    notes: "Official LSAC prep materials"
  },
  %{
    test_type: "lsat",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/prep/lsat",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 20
  },
  %{
    test_type: "lsat",
    catalog_subject: nil,
    url_or_pattern: "https://www.magoosh.com/lsat/lsat-practice-questions",
    domain: "magoosh.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 15
  },

  # ── MCAT ────────────────────────────────────────────────────────────────
  %{
    test_type: "mcat",
    catalog_subject: nil,
    url_or_pattern: "https://students-residents.aamc.org/prepare-mcat-exam/official-mcat-prep",
    domain: "aamc.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 30,
    notes: "Official AAMC MCAT prep"
  },
  %{
    test_type: "mcat",
    catalog_subject: nil,
    url_or_pattern: "https://www.khanacademy.org/test-prep/mcat",
    domain: "khanacademy.org",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 18
  },
  %{
    test_type: "mcat",
    catalog_subject: nil,
    url_or_pattern: "https://www.magoosh.com/mcat/mcat-practice-questions",
    domain: "magoosh.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 15
  },

  # ── PRAXIS ──────────────────────────────────────────────────────────────
  %{
    test_type: "praxis",
    catalog_subject: nil,
    url_or_pattern: "https://www.ets.org/praxis/prepare/materials",
    domain: "ets.org",
    source_type: "official",
    tier: 1,
    avg_questions_per_page: 30,
    notes: "Official ETS Praxis prep"
  },
  %{
    test_type: "praxis",
    catalog_subject: nil,
    url_or_pattern: "https://www.varsitytutors.com/praxis-practice-tests",
    domain: "varsitytutors.com",
    source_type: "practice_test",
    tier: 2,
    avg_questions_per_page: 20
  },
  %{
    test_type: "praxis",
    catalog_subject: nil,
    url_or_pattern: "https://www.prepscholar.com/praxis/s/questions",
    domain: "prepscholar.com",
    source_type: "question_bank",
    tier: 2,
    avg_questions_per_page: 15
  }
]

now = DateTime.utc_now() |> DateTime.truncate(:second)

{inserted, _} =
  Repo.insert_all(
    SourceRegistryEntry,
    Enum.map(entries, fn e ->
      Map.merge(e, %{
        id: Ecto.UUID.generate(),
        is_enabled: true,
        consecutive_failures: 0,
        inserted_at: now,
        updated_at: now
      })
    end),
    on_conflict: :nothing,
    conflict_target: [:test_type, :catalog_subject, :url_or_pattern]
  )

IO.puts("Source registry seeded: #{inserted} new entries (#{length(entries) - inserted} already existed)")
