# priv/repo/seeds/sat_courses.exs
# Run with: mix run priv/repo/seeds/sat_courses.exs
#
# Creates the SAT Math and SAT Reading & Writing premium catalog courses,
# their chapter/section structure, test format templates (for Exam Simulation),
# and the SAT Full Prep Bundle.
#
# IMPORTANT: This script creates structural scaffolding only.
# NO question content is seeded here — all questions come from AI generation
# workers after the course is triggered for processing.

alias FunSheep.Repo
alias FunSheep.Courses.{Course, Chapter, Section, CourseBundle}
alias FunSheep.Assessments.TestFormatTemplate

import Ecto.Query

IO.puts("Seeding SAT courses...")

# ── Helper ───────────────────────────────────────────────────────────────────

defmodule SATSeed do
  def find_or_create_course(attrs) do
    case Repo.one(
           from c in Course,
             where:
               c.catalog_test_type == "sat" and c.catalog_subject == ^attrs.catalog_subject
         ) do
      nil ->
        %Course{}
        |> Course.changeset(attrs)
        |> Repo.insert!()

      existing ->
        # Always merge metadata so generation_config and score_predictor_weights
        # are kept current even when the course already exists.
        new_metadata = Map.merge(existing.metadata || %{}, attrs.metadata || %{})

        {:ok, updated} =
          existing
          |> Course.changeset(%{metadata: new_metadata})
          |> Repo.update()

        updated
    end
  end

  def seed_chapters(course, chapters_spec) do
    Enum.with_index(chapters_spec, fn {chapter_name, sections}, pos ->
      chapter =
        case Repo.one(
               from ch in Chapter,
                 where: ch.course_id == ^course.id and ch.name == ^chapter_name
             ) do
          nil ->
            Repo.insert!(%Chapter{course_id: course.id, name: chapter_name, position: pos})

          existing ->
            existing
        end

      Enum.with_index(sections, fn section_name, sec_pos ->
        case Repo.one(
               from s in Section,
                 where: s.chapter_id == ^chapter.id and s.name == ^section_name
             ) do
          nil ->
            Repo.insert!(%Section{
              chapter_id: chapter.id,
              name: section_name,
              position: sec_pos
            })

          existing ->
            existing
        end
      end)
    end)
  end

  def seed_format_template(course, template_attrs) do
    case Repo.one(
           from t in TestFormatTemplate,
             where: t.course_id == ^course.id and t.name == ^template_attrs.name
         ) do
      nil ->
        Repo.insert!(%TestFormatTemplate{
          course_id: course.id,
          name: template_attrs.name,
          structure: template_attrs.structure
        })

      existing ->
        existing
    end
  end
end

# ── SAT Math ─────────────────────────────────────────────────────────────────

math_course =
  SATSeed.find_or_create_course(%{
    name: "SAT Math",
    subject: "Mathematics",
    grades: ["College Prep"],
    description:
      "Complete SAT Math preparation covering all four domains: Algebra, Advanced Math, " <>
        "Problem-Solving & Data Analysis, and Geometry & Trigonometry. Adaptive practice " <>
        "targets your weak areas and predicts your section score.",
    catalog_test_type: "sat",
    catalog_subject: "mathematics",
    catalog_level: "full_section",
    is_premium_catalog: true,
    access_level: "premium",
    price_cents: 2900,
    currency: "usd",
    price_label: "One-time purchase",
    sample_question_count: 10,
    processing_status: "pending",
    metadata: %{
      "generation_config" => %{
        "prompt_context" =>
          "Digital SAT Math — adaptive exam, 4-option MCQ or numeric free-entry, " <>
            "calculator always available. Domains: Algebra (35%), Advanced Math (35%), " <>
            "Problem-Solving & Data Analysis (15%), Geometry & Trigonometry (15%).",
        "validation_rules" => %{
          "mcq_option_count" => 4,
          "answer_labels" => ["A", "B", "C", "D"]
        }
      },
      "score_predictor_weights" => %{
        "algebra" => 0.35,
        "advanced_math" => 0.35,
        "problem_solving_data_analysis" => 0.15,
        "geometry_trigonometry" => 0.15
      },
      "score_range" => [200, 800]
    }
  })

IO.puts("SAT Math course: #{math_course.id}")

math_chapters = [
  {"Algebra",
   [
     "Linear Equations in One Variable",
     "Linear Equations in Two Variables",
     "Linear Functions and Graphs",
     "Systems of Two Linear Equations",
     "Linear Inequalities",
     "Word Problems: Setting Up Equations"
   ]},
  {"Advanced Math",
   [
     "Quadratic Equations — Factoring",
     "Quadratic Equations — Completing the Square",
     "Quadratic Equations — Quadratic Formula",
     "Quadratic Functions — Vertex and Axis of Symmetry",
     "Polynomial Functions",
     "Exponential Functions and Growth",
     "Function Notation and Composition",
     "Radical and Absolute Value Functions"
   ]},
  {"Problem-Solving & Data Analysis",
   [
     "Ratios, Rates, and Proportions",
     "Percentages",
     "Unit Conversion",
     "Statistics — Central Tendency",
     "Statistics — Spread and Distribution",
     "Two-Way Tables",
     "Probability",
     "Data Interpretation — Graphs and Charts"
   ]},
  {"Geometry & Trigonometry",
   [
     "Lines and Angles",
     "Triangle Properties",
     "Area and Perimeter",
     "Circles — Arc, Sector, Central Angle",
     "Volume",
     "Pythagorean Theorem",
     "Right Triangle Trigonometry",
     "Unit Circle and Special Angles"
   ]}
]

SATSeed.seed_chapters(math_course, math_chapters)

SATSeed.seed_format_template(math_course, %{
  name: "SAT Math — Full Exam",
  structure: %{
    "time_limit_minutes" => 70,
    "sections" => [
      %{
        "name" => "Math Module 1",
        "question_type" => "mixed",
        "count" => 22,
        "time_limit_minutes" => 35,
        "chapter_ids" => []
      },
      %{
        "name" => "Math Module 2",
        "question_type" => "mixed",
        "count" => 22,
        "time_limit_minutes" => 35,
        "chapter_ids" => []
      }
    ]
  }
})

IO.puts("SAT Math chapters and sections seeded.")

# ── SAT Reading & Writing ─────────────────────────────────────────────────────

rw_course =
  SATSeed.find_or_create_course(%{
    name: "SAT Reading & Writing",
    subject: "English Language Arts",
    grades: ["College Prep"],
    description:
      "Complete SAT Reading & Writing preparation covering all four domains: Craft & Structure, " <>
        "Information & Ideas, Expression of Ideas, and Standard English Conventions. Master " <>
        "grammar rules, vocabulary in context, and passage comprehension.",
    catalog_test_type: "sat",
    catalog_subject: "reading_writing",
    catalog_level: "full_section",
    is_premium_catalog: true,
    access_level: "premium",
    price_cents: 2900,
    currency: "usd",
    price_label: "One-time purchase",
    sample_question_count: 10,
    processing_status: "pending",
    metadata: %{
      "generation_config" => %{
        "prompt_context" =>
          "Digital SAT Reading & Writing — adaptive exam, 4-option MCQ, passage-based. " <>
            "Domains: Craft & Structure (28%), Information & Ideas (26%), " <>
            "Expression of Ideas (20%), Standard English Conventions (26%).",
        "validation_rules" => %{
          "mcq_option_count" => 4,
          "answer_labels" => ["A", "B", "C", "D"]
        }
      },
      "score_predictor_weights" => %{
        "craft_and_structure" => 0.28,
        "information_and_ideas" => 0.26,
        "expression_of_ideas" => 0.20,
        "standard_english_conventions" => 0.26
      },
      "score_range" => [200, 800]
    }
  })

IO.puts("SAT Reading & Writing course: #{rw_course.id}")

rw_chapters = [
  {"Craft & Structure",
   [
     "Words in Context — Meaning",
     "Words in Context — Tone and Connotation",
     "Text Structure and Purpose",
     "Cross-Text Connections"
   ]},
  {"Information & Ideas",
   [
     "Central Idea and Details",
     "Evidence — Textual Support",
     "Evidence — Graphic and Data Integration",
     "Inferences"
   ]},
  {"Expression of Ideas",
   [
     "Rhetorical Goals and Purpose",
     "Transitions",
     "Parallel Structure and Style"
   ]},
  {"Standard English Conventions",
   [
     "Punctuation — Commas",
     "Punctuation — Semicolons and Colons",
     "Punctuation — Dashes and Parentheses",
     "Subject-Verb Agreement",
     "Pronoun-Antecedent Agreement",
     "Pronoun Case",
     "Verb Tense and Consistency",
     "Modifier Placement",
     "Run-Ons, Fragments, and Sentence Boundaries"
   ]}
]

SATSeed.seed_chapters(rw_course, rw_chapters)

SATSeed.seed_format_template(rw_course, %{
  name: "SAT Reading & Writing — Full Exam",
  structure: %{
    "time_limit_minutes" => 64,
    "sections" => [
      %{
        "name" => "Reading & Writing Module 1",
        "question_type" => "multiple_choice",
        "count" => 27,
        "time_limit_minutes" => 32,
        "chapter_ids" => []
      },
      %{
        "name" => "Reading & Writing Module 2",
        "question_type" => "multiple_choice",
        "count" => 27,
        "time_limit_minutes" => 32,
        "chapter_ids" => []
      }
    ]
  }
})

IO.puts("SAT Reading & Writing chapters and sections seeded.")

# ── SAT Full Prep Bundle ──────────────────────────────────────────────────────

bundle_name = "SAT Full Prep Bundle"

unless Repo.one(from b in CourseBundle, where: b.name == ^bundle_name) do
  Repo.insert!(%CourseBundle{
    name: bundle_name,
    description:
      "Complete SAT preparation — Math and Reading & Writing. Save $9 vs. buying separately.",
    price_cents: 4900,
    currency: "usd",
    course_ids: [math_course.id, rw_course.id],
    is_active: true,
    catalog_test_type: "sat"
  })

  IO.puts("SAT Full Prep Bundle created.")
end

IO.puts("Done! SAT seed complete.")
IO.puts("  Math course ID: #{math_course.id}")
IO.puts("  RW course ID:   #{rw_course.id}")
