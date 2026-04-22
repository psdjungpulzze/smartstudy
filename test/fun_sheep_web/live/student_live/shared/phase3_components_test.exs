defmodule FunSheepWeb.StudentLive.Shared.Phase3ComponentsTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accountability.StudyGoal

  alias FunSheepWeb.StudentLive.Shared.{
    AssignmentsPanel,
    ConversationPrompts,
    GoalsPanel,
    ShareTriggers
  }

  describe "GoalsPanel.panel/1" do
    test "renders empty state" do
      html =
        render_component(&GoalsPanel.panel/1,
          pending_for_viewer: [],
          active_goals: [],
          progress_by_goal: %{},
          student_id: "stu-1"
        )

      assert html =~ "No goals yet"
    end

    test "renders a pending goal with Accept / Counter / Decline" do
      goal = %StudyGoal{
        id: "g1",
        goal_type: :daily_minutes,
        target_value: 30,
        proposed_by: :student
      }

      html =
        render_component(&GoalsPanel.panel/1,
          pending_for_viewer: [goal],
          active_goals: [],
          progress_by_goal: %{},
          student_id: "stu-1"
        )

      assert html =~ "Awaiting your response"
      assert html =~ "Accept"
      assert html =~ "Counter"
      assert html =~ "Decline"
      assert html =~ "30 min/day"
    end

    test "renders active goal with progress" do
      goal = %StudyGoal{
        id: "g2",
        goal_type: :daily_minutes,
        target_value: 30,
        status: :active
      }

      progress = %{
        status: :ok,
        actual_daily_minutes: 25,
        target_daily_minutes: 30,
        on_track?: false,
        adherence_pct: 83
      }

      html =
        render_component(&GoalsPanel.panel/1,
          pending_for_viewer: [],
          active_goals: [goal],
          progress_by_goal: %{"g2" => progress},
          student_id: "stu-1"
        )

      assert html =~ "30 min/day"
      assert html =~ "behind"
      assert html =~ "25 min/day so far"
    end
  end

  describe "AssignmentsPanel.panel/1" do
    test "empty state" do
      html = render_component(&AssignmentsPanel.panel/1, assignments: [], open_slots: 3)
      assert html =~ "No open assignments"
      assert html =~ "3 open slots"
    end

    test "renders an assignment" do
      assignment = %{
        id: "a1",
        question_count: 10,
        due_date: Date.utc_today(),
        questions_attempted: 5,
        questions_correct: 4,
        status: :in_progress,
        section: %{name: "Adding fractions"}
      }

      html =
        render_component(&AssignmentsPanel.panel/1, assignments: [assignment], open_slots: 2)

      assert html =~ "Adding fractions"
      assert html =~ "10 questions"
      assert html =~ "In progress"
      assert html =~ "4/5"
    end
  end

  describe "ConversationPrompts.card/1" do
    test "empty state" do
      html = render_component(&ConversationPrompts.card/1, prompts: [])
      assert html =~ "Nothing to flag this week"
    end

    test "renders prompt with opener" do
      prompts = [
        %{
          kind: :missed_sessions,
          student_id: "s1",
          goal_id: "g1",
          summary: "has missed 3 study days",
          opener: "What got in the way this week?",
          rationale: "Open questions work better than directives."
        }
      ]

      html = render_component(&ConversationPrompts.card/1, prompts: prompts)
      assert html =~ "has missed 3 study days"
      assert html =~ "What got in the way"
      assert html =~ "Open questions"
    end
  end

  describe "ShareTriggers.banner/1" do
    test "doesn't render when triggers are empty" do
      html = render_component(&ShareTriggers.banner/1, triggers: [], student_id: "s1")
      refute html =~ "Milestone reached"
    end

    test "renders share CTA for goal_achieved" do
      triggers = [
        %{
          kind: :goal_achieved,
          goal_id: "g1",
          goal_type: :streak_days,
          target_value: 7,
          achieved_at: DateTime.utc_now()
        }
      ]

      html = render_component(&ShareTriggers.banner/1, triggers: triggers, student_id: "s1")
      assert html =~ "Milestone reached"
      assert html =~ "7-day streak"
      assert html =~ "Share"
    end
  end
end
