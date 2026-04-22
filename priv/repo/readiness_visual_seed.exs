#
# Seed script for visual-verifying AssessmentLive readiness-block states.
# Creates four courses covering every readiness branch, plus a ready
# happy-path course. Prints each course/schedule ID with the URL to test.
#
# Run with:
#   MIX_ENV=dev mix run priv/repo/readiness_visual_seed.exs
#
# Intended to be invoked from scripts / test harnesses only, not in prod.
#

alias FunSheep.{Repo, Courses, Questions}
alias FunSheep.Accounts.UserRole

import Ecto.Query

student =
  Repo.one(from(ur in UserRole, where: ur.role == :student, limit: 1)) ||
    raise "No student user role in dev DB — log in via /dev/login first"

# -- Helpers --

create_course = fn name, status ->
  {:ok, course} =
    %FunSheep.Courses.Course{}
    |> FunSheep.Courses.Course.changeset(%{
      name: name,
      subject: "Biology",
      grade: "10",
      created_by_id: student.id,
      processing_status: status,
      processing_step:
        case status do
          "validating" -> "Validating questions…"
          "failed" -> "AI service unavailable — please try again later."
          _ -> nil
        end
    })
    |> Repo.insert()

  course
end

create_chapter = fn course, name, pos ->
  {:ok, ch} = Courses.create_chapter(%{course_id: course.id, name: name, position: pos})
  ch
end

create_section = fn chapter, name ->
  {:ok, s} = Courses.create_section(%{chapter_id: chapter.id, name: name, position: 1})
  s
end

create_question = fn course, chapter, section, idx ->
  {:ok, q} =
    Questions.create_question(%{
      validation_status: :passed,
      content: "Visual seed question #{idx} — what is #{idx} + 1?",
      answer: "A",
      question_type: :multiple_choice,
      difficulty: :easy,
      options: %{"A" => to_string(idx + 1), "B" => "42", "C" => "0", "D" => "infinity"},
      course_id: course.id,
      chapter_id: chapter.id,
      section_id: section.id,
      classification_status: :ai_classified
    })

  q
end

create_schedule = fn course, name, chapter_ids ->
  {:ok, s} =
    Oban.Testing.with_testing_mode(:manual, fn ->
      FunSheep.Assessments.create_test_schedule(%{
        name: name,
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => chapter_ids},
        user_role_id: student.id,
        course_id: course.id
      })
    end)

  s
end

# --- 1. Happy path: ready course with enough passed+classified questions ---

ready_course = create_course.("ReadinessViz — ready", "ready")
ready_ch = create_chapter.(ready_course, "Chapter 1", 1)
ready_sec = create_section.(ready_ch, "Skill A")
for i <- 1..4, do: create_question.(ready_course, ready_ch, ready_sec, i)
ready_schedule = create_schedule.(ready_course, "Ready Quiz", [ready_ch.id])

# --- 2. :scope_empty — course ready, chapter has no questions ---

empty_course = create_course.("ReadinessViz — scope_empty", "ready")
empty_ch = create_chapter.(empty_course, "Empty Chapter", 1)
_empty_sec = create_section.(empty_ch, "Empty Skill")
empty_schedule = create_schedule.(empty_course, "Empty Quiz", [empty_ch.id])

# --- 3. :scope_partial — course ready, ch1 has questions, ch2 doesn't ---

partial_course = create_course.("ReadinessViz — scope_partial", "ready")
p_ch1 = create_chapter.(partial_course, "Ready Chapter", 1)
p_sec1 = create_section.(p_ch1, "Skill")
for i <- 1..3, do: create_question.(partial_course, p_ch1, p_sec1, i)
p_ch2 = create_chapter.(partial_course, "Missing Chapter", 2)
partial_schedule = create_schedule.(partial_course, "Partial Quiz", [p_ch1.id, p_ch2.id])

# --- 4. :course_not_ready — course validating, no questions yet ---

validating_course = create_course.("ReadinessViz — validating", "validating")
v_ch = create_chapter.(validating_course, "Ch", 1)
validating_schedule = create_schedule.(validating_course, "Validating Quiz", [v_ch.id])

# --- 5. :course_failed — course failed ---

failed_course = create_course.("ReadinessViz — failed", "failed")
f_ch = create_chapter.(failed_course, "Ch", 1)
failed_schedule = create_schedule.(failed_course, "Failed Quiz", [f_ch.id])

IO.puts("\n=== Readiness visual seed URLs ===")

for {label, course, schedule} <- [
      {"1. ready (happy path)", ready_course, ready_schedule},
      {"2. scope_empty", empty_course, empty_schedule},
      {"3. scope_partial", partial_course, partial_schedule},
      {"4. course_not_ready(validating)", validating_course, validating_schedule},
      {"5. course_failed", failed_course, failed_schedule}
    ] do
  IO.puts("#{label} /courses/#{course.id}/tests/#{schedule.id}/assess")
end

IO.puts("")
