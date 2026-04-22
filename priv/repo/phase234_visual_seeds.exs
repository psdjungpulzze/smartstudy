# Visual-verification seeds for Phases 2–4. Local dev only.
#
# Produces:
# - A linked parent+student pair (matching the dev-login identities so the
#   visual tester can just click "Parent" on /dev/login).
# - A course (grade "10") with two chapters + two sections each.
# - Questions + attempts to populate the topic mastery map + drill-down.
# - 30 study sessions across 14 days covering every time window so the
#   activity timeline, heatmap, and wellbeing classifier all light up.
# - A test schedule with a target_readiness_score set — unlocks forecast.
# - 4 weekly readiness snapshots so the percentile trend sparkline renders.
# - A 22-student cohort in the same course+grade so cohort bands clear
#   the 20-student threshold.
# - An active daily-minutes goal (with progress) + a student-proposed
#   goal awaiting the parent (populates the GoalsPanel "Awaiting your
#   response" section) + an :achieved goal for the ShareTriggers banner.
# - An open practice assignment so AssignmentsPanel has a populated row.
#
# Run with: MIX_ENV=dev mix run priv/repo/phase234_visual_seeds.exs

alias FunSheep.{Accountability, Accounts, Assessments, Courses, Questions, Repo}
alias FunSheep.Accountability.StudyGoal
alias FunSheep.Assessments.{ReadinessScore, TestSchedule}
alias FunSheep.Engagement.StudySession
alias FunSheep.Geo
alias FunSheep.Questions.QuestionAttempt

require Ecto.Query
import Ecto.Query, only: [from: 2]

# ── Geo prerequisites ─────────────────────────────────────────────────────
{:ok, country} =
  %Geo.Country{}
  |> Geo.Country.changeset(%{name: "Seedland", code: "SEED"})
  |> Repo.insert()

{:ok, state} =
  %Geo.State{}
  |> Geo.State.changeset(%{name: "Seed State", country_id: country.id})
  |> Repo.insert()

{:ok, district} =
  %Geo.District{}
  |> Geo.District.changeset(%{name: "Seed District", state_id: state.id})
  |> Repo.insert()

{:ok, school} =
  %Geo.School{}
  |> Geo.School.changeset(%{name: "Seed School", district_id: district.id})
  |> Repo.insert()

# ── Dev users (match /dev/login identities) ───────────────────────────────
{:ok, parent} =
  Accounts.create_user_role(%{
    interactor_user_id: "dev_interactor_parent",
    role: :parent,
    email: "dev_parent@studysmart.test",
    display_name: "Dev Parent",
    school_id: school.id,
    digest_frequency: :weekly
  })

{:ok, student} =
  Accounts.create_user_role(%{
    interactor_user_id: "dev_interactor_student",
    role: :student,
    email: "dev_student@studysmart.test",
    display_name: "Dev Student",
    grade: "10",
    school_id: school.id,
    timezone: "America/Los_Angeles"
  })

{:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
{:ok, _} = Accounts.accept_guardian_invite(sg.id)

# ── Course / chapters / sections ──────────────────────────────────────────
{:ok, course} =
  Courses.create_course(%{
    name: "Algebra I",
    subject: "Math",
    grade: "10",
    school_id: school.id,
    created_by_id: student.id
  })

{:ok, chapter_a} = Courses.create_chapter(%{name: "Fractions", position: 1, course_id: course.id})
{:ok, chapter_b} = Courses.create_chapter(%{name: "Geometry", position: 2, course_id: course.id})

{:ok, sec_a1} = Courses.create_section(%{name: "Adding", position: 1, chapter_id: chapter_a.id})
{:ok, sec_a2} = Courses.create_section(%{name: "Multiplying", position: 2, chapter_id: chapter_a.id})
{:ok, sec_b1} = Courses.create_section(%{name: "Triangles", position: 1, chapter_id: chapter_b.id})
{:ok, sec_b2} = Courses.create_section(%{name: "Circles", position: 2, chapter_id: chapter_b.id})

sections = [sec_a1, sec_a2, sec_b1, sec_b2]

# ── Questions + attempts (topic mastery map) ──────────────────────────────
questions_per_section = 3

questions =
  for section <- sections, i <- 1..questions_per_section do
    {:ok, q} =
      Questions.create_question(%{
        content: "Q#{i} for #{section.name}",
        answer: "A",
        question_type: :short_answer,
        difficulty: :medium,
        course_id: course.id,
        chapter_id: section.chapter_id,
        section_id: section.id,
        validation_status: :passed
      })

    {section, q}
  end

now = DateTime.utc_now() |> DateTime.truncate(:second)

for {{section, q}, idx} <- Enum.with_index(questions) do
  # Mix correct/incorrect so each section gets a plausible accuracy
  correct? = rem(idx, 3) != 0

  for offset <- [0, 3, 7] do
    {:ok, _} =
      %QuestionAttempt{}
      |> QuestionAttempt.changeset(%{
        user_role_id: student.id,
        question_id: q.id,
        is_correct: correct?,
        time_taken_seconds: 25 + rem(idx, 10),
        answer_given: "x"
      })
      |> Repo.insert()

    _ = section
    _ = offset
  end
end

# ── Study sessions (timeline + heatmap + forecaster inputs) ───────────────
windows = ["morning", "afternoon", "evening", "night"]

for day_offset <- 0..13 do
  window = Enum.at(windows, rem(day_offset, length(windows)))
  attempted = 10 + rem(day_offset, 5)
  correct_count = attempted - rem(day_offset, 3)

  {:ok, _} =
    %StudySession{}
    |> StudySession.changeset(%{
      session_type: Enum.random(~w(practice review quick_test)),
      time_window: window,
      questions_attempted: attempted,
      questions_correct: correct_count,
      duration_seconds: 600 + day_offset * 30,
      user_role_id: student.id,
      course_id: course.id,
      completed_at: DateTime.add(now, -day_offset, :day)
    })
    |> Repo.insert()
end

# ── Test schedule + target score ──────────────────────────────────────────
{:ok, schedule} =
  Assessments.create_test_schedule(%{
    name: "Unit Exam",
    test_date: Date.add(Date.utc_today(), 21),
    scope: %{"chapter_ids" => [chapter_a.id, chapter_b.id]},
    user_role_id: student.id,
    course_id: course.id
  })

{:ok, schedule} = Assessments.set_target_readiness(schedule, 85, :guardian)

# ── Weekly readiness snapshots for percentile history + forecaster ───────
defmodule S do
  def snap!(student_id, schedule_id, score, days_ago) do
    {:ok, rs} =
      %FunSheep.Assessments.ReadinessScore{}
      |> FunSheep.Assessments.ReadinessScore.changeset(%{
        user_role_id: student_id,
        test_schedule_id: schedule_id,
        aggregate_score: score,
        chapter_scores: %{},
        topic_scores: %{},
        skill_scores: %{},
        calculated_at: DateTime.utc_now()
      })
      |> FunSheep.Repo.insert()

    ts =
      DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second)

    FunSheep.Repo.update_all(
      from(r in FunSheep.Assessments.ReadinessScore, where: r.id == ^rs.id),
      set: [inserted_at: ts, calculated_at: ts]
    )
  end
end

for {score, days_ago} <- [{55.0, 21}, {63.0, 14}, {69.0, 7}, {75.0, 0}] do
  S.snap!(student.id, schedule.id, score, days_ago)
end

# ── Cohort: 22 extra students — each snapshotted in every of the last 4
# weekly buckets so the percentile-trend sparkline actually has data to
# plot (spec §6.1 requires ≥2 students per bucket for the sample to clear
# the small-cohort filter).
for i <- 1..22 do
  {:ok, peer_school} =
    %Geo.School{}
    |> Geo.School.changeset(%{name: "Peer #{i}", district_id: district.id})
    |> Repo.insert()

  {:ok, peer} =
    Accounts.create_user_role(%{
      interactor_user_id: "peer_#{i}",
      role: :student,
      email: "peer#{i}@seed.test",
      display_name: "Peer #{i}",
      grade: "10",
      school_id: peer_school.id
    })

  {:ok, peer_schedule} =
    Assessments.create_test_schedule(%{
      name: "Peer Exam",
      test_date: Date.add(Date.utc_today(), 21),
      scope: %{"chapter_ids" => []},
      user_role_id: peer.id,
      course_id: course.id
    })

  base = 40.0 + i * 2.5

  for {drift, days_ago} <- [{-4.0, 21}, {-2.0, 14}, {-1.0, 7}, {0.0, 0}] do
    S.snap!(peer.id, peer_schedule.id, base + drift, days_ago)
  end
end

# ── Accountability: goals + assignment ────────────────────────────────────
{:ok, active_goal} =
  Accountability.propose_goal(parent.id, %{
    student_id: student.id,
    goal_type: "daily_minutes",
    target_value: 30,
    start_date: Date.add(Date.utc_today(), -6)
  })

{:ok, _active} = Accountability.accept_goal(active_goal.id, :student)

# Student-proposed pending goal — populates the "Awaiting your response" row
{:ok, pending} =
  Accountability.propose_goal(parent.id, %{
    student_id: student.id,
    goal_type: "weekly_practice_count",
    target_value: 5,
    start_date: Date.utc_today()
  })

{:ok, _} =
  pending
  |> Ecto.Changeset.change(%{proposed_by: :student})
  |> Repo.update()

# Achieved goal to fire the ShareTriggers banner
{:ok, achieved} =
  Accountability.propose_goal(parent.id, %{
    student_id: student.id,
    goal_type: "streak_days",
    target_value: 7,
    start_date: Date.add(Date.utc_today(), -14)
  })

{:ok, achieved} = Accountability.accept_goal(achieved.id, :student)
{:ok, _} = Accountability.mark_goal_achieved(achieved)

# Practice assignment — populates AssignmentsPanel
{:ok, _} =
  Accountability.assign_practice(parent.id, student.id, sec_a2.id, question_count: 10)

IO.puts("\n✅ Visual-verification seeds loaded.")
IO.puts("   Parent: dev_parent@studysmart.test (role=parent)")
IO.puts("   Student: dev_student@studysmart.test (role=student, grade=10)")
IO.puts("   Log in at /dev/login, pick Parent, land on /parent.")
