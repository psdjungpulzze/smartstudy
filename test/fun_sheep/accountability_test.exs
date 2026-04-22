defmodule FunSheep.AccountabilityTest do
  @moduledoc """
  Covers `FunSheep.Accountability` — joint goals, bounded parent-assigned
  practice, conversation prompts, share triggers (spec §7.1–§7.3).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Accountability, Accounts, Courses, Repo}
  alias FunSheep.Accountability.{PracticeAssignment, StudyGoal}
  alias FunSheep.ContentFixtures
  alias FunSheep.Engagement.StudySession

  setup do
    parent = ContentFixtures.create_user_role(%{role: :parent})
    student = ContentFixtures.create_user_role(%{role: :student, grade: "10"})

    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)

    %{parent: parent, student: student}
  end

  describe "propose_goal/2" do
    test "inserts a :proposed goal", %{parent: p, student: s} do
      assert {:ok, %StudyGoal{} = goal} =
               Accountability.propose_goal(p.id, %{
                 student_id: s.id,
                 goal_type: "daily_minutes",
                 target_value: 30,
                 start_date: Date.utc_today()
               })

      assert goal.status == :proposed
      assert goal.proposed_by == :guardian
      assert goal.target_value == 30
    end

    test "refuses when guardian is not linked" do
      stranger = ContentFixtures.create_user_role(%{role: :parent})
      student = ContentFixtures.create_user_role(%{role: :student})

      assert {:error, :unauthorized} =
               Accountability.propose_goal(stranger.id, %{
                 student_id: student.id,
                 goal_type: "daily_minutes",
                 target_value: 30,
                 start_date: Date.utc_today()
               })
    end

    test "rejects target_value out of range", %{parent: p, student: s} do
      assert {:error, _} =
               Accountability.propose_goal(p.id, %{
                 student_id: s.id,
                 goal_type: "daily_minutes",
                 target_value: 1000,
                 start_date: Date.utc_today()
               })
    end
  end

  describe "accept_goal/2" do
    test "student can accept a guardian proposal", %{parent: p, student: s} do
      {:ok, goal} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 30,
          start_date: Date.utc_today()
        })

      assert {:ok, accepted} = Accountability.accept_goal(goal.id, :student)
      assert accepted.status == :active
      assert accepted.accepted_at
    end

    test "guardian can't accept their own proposal", %{parent: p, student: s} do
      {:ok, goal} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 30,
          start_date: Date.utc_today()
        })

      assert {:error, :cannot_accept_own_proposal} =
               Accountability.accept_goal(goal.id, :guardian)
    end
  end

  describe "counter_goal/3" do
    test "abandons original and inserts a new counter-proposal", %{parent: p, student: s} do
      {:ok, original} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 60,
          start_date: Date.utc_today()
        })

      assert {:ok, counter} =
               Accountability.counter_goal(original.id, :student, %{
                 target_value: 30
               })

      assert counter.proposed_by == :student
      assert counter.target_value == 30
      assert Repo.get!(StudyGoal, original.id).status == :abandoned
    end
  end

  describe "decline_goal/3" do
    test "marks proposal abandoned with a reason", %{parent: p, student: s} do
      {:ok, goal} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 30,
          start_date: Date.utc_today()
        })

      assert {:ok, declined} = Accountability.decline_goal(goal.id, :student, "too much")
      assert declined.status == :abandoned
      assert declined.decline_reason == "too much"
    end
  end

  describe "goal_progress/1" do
    defp insert_session!(s, attrs) do
      defaults = %{
        session_type: "practice",
        time_window: "morning",
        questions_attempted: 5,
        questions_correct: 4,
        duration_seconds: 900,
        user_role_id: s.id,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      {:ok, _} =
        %StudySession{}
        |> StudySession.changeset(Map.merge(defaults, attrs))
        |> Repo.insert()
    end

    test "daily_minutes progress uses real session minutes", %{parent: p, student: s} do
      for offset <- [0, 1, 2, 3] do
        insert_session!(s, %{
          completed_at:
            DateTime.utc_now()
            |> DateTime.add(-offset, :day)
            |> DateTime.truncate(:second),
          duration_seconds: 600
        })
      end

      {:ok, goal} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 15,
          start_date: Date.add(Date.utc_today(), -5)
        })

      {:ok, goal} = Accountability.accept_goal(goal.id, :student)

      progress = Accountability.goal_progress(goal)
      assert progress.status == :ok
      assert progress.minutes_total == 40
      assert progress.days_elapsed == 5
      assert progress.actual_daily_minutes == 8
      refute progress.on_track?
    end
  end

  describe "assign_practice/4" do
    setup %{parent: p, student: s} do
      course = ContentFixtures.create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "C1", position: 1, course_id: course.id})
      {:ok, section} = Courses.create_section(%{name: "S1", position: 1, chapter_id: chapter.id})

      %{parent: p, student: s, course: course, chapter: chapter, section: section}
    end

    test "creates an assignment respecting the question cap", ctx do
      assert {:ok, %PracticeAssignment{} = a} =
               Accountability.assign_practice(ctx.parent.id, ctx.student.id, ctx.section.id,
                 question_count: 15
               )

      assert a.question_count == 15
      assert a.section_id == ctx.section.id
    end

    test "rejects > 20 questions", ctx do
      assert {:error, :too_many_questions} =
               Accountability.assign_practice(ctx.parent.id, ctx.student.id, ctx.section.id,
                 question_count: 21
               )
    end

    test "rejects when 3 open assignments already exist", ctx do
      for i <- 1..3 do
        {:ok, _} =
          Accountability.assign_practice(ctx.parent.id, ctx.student.id, ctx.section.id,
            question_count: i + 1
          )
      end

      assert {:error, :too_many_open_assignments} =
               Accountability.assign_practice(ctx.parent.id, ctx.student.id, ctx.section.id,
                 question_count: 5
               )
    end

    test "rejects unauthorized guardian", ctx do
      stranger = ContentFixtures.create_user_role(%{role: :parent})

      assert {:error, :unauthorized} =
               Accountability.assign_practice(stranger.id, ctx.student.id, ctx.section.id,
                 question_count: 10
               )
    end
  end

  describe "conversation_prompts_for_parent/2" do
    test "returns a missed-sessions prompt when behind on daily_minutes goal", %{
      parent: p,
      student: s
    } do
      {:ok, goal} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 60,
          start_date: Date.add(Date.utc_today(), -7)
        })

      {:ok, _} = Accountability.accept_goal(goal.id, :student)

      [prompt] = Accountability.conversation_prompts_for_parent(p.id, s.id)
      assert prompt.kind == :missed_sessions
      assert prompt.opener =~ "What's been hardest"
    end

    test "returns [] for unauthorized guardian" do
      stranger = ContentFixtures.create_user_role(%{role: :parent})
      student = ContentFixtures.create_user_role(%{role: :student})

      assert Accountability.conversation_prompts_for_parent(stranger.id, student.id) == []
    end
  end

  describe "share_triggers/2" do
    test "surfaces recent :achieved goals", %{parent: p, student: s} do
      {:ok, goal} =
        Accountability.propose_goal(p.id, %{
          student_id: s.id,
          goal_type: "daily_minutes",
          target_value: 30,
          start_date: Date.utc_today()
        })

      {:ok, goal} = Accountability.accept_goal(goal.id, :student)
      {:ok, _} = Accountability.mark_goal_achieved(goal)

      [trigger] = Accountability.share_triggers(p.id, s.id)
      assert trigger.kind == :goal_achieved
    end
  end
end
