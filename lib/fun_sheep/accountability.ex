defmodule FunSheep.Accountability do
  @moduledoc """
  Accountability context (spec §7) — joint study goals and bounded
  parent-assigned practice.

  Every mutating function guards on `FunSheep.Accounts.guardian_has_access?/2`
  when a guardian is involved, per spec §9.1. The context never fabricates
  progress numbers: `goal_progress/1` reflects real recorded activity or
  returns `:insufficient_data`.
  """

  import Ecto.Query, warn: false

  alias FunSheep.Accountability.{PracticeAssignment, StudyGoal}
  alias FunSheep.{Accounts, Gamification, Repo}

  @max_open_assignments_per_student 3
  @default_assignment_due_days 3
  @default_practice_questions 10

  def max_open_assignments_per_student, do: @max_open_assignments_per_student
  def max_questions_per_assignment, do: PracticeAssignment.max_questions()

  ## ── Study Goals (§7.1) ───────────────────────────────────────────────────

  @doc """
  Parent proposes a goal for a linked student. Creates a `:proposed` goal
  the student must accept / counter / decline before it counts toward
  tracking.
  """
  def propose_goal(guardian_id, attrs) when is_binary(guardian_id) and is_map(attrs) do
    student_id = attrs[:student_id] || attrs["student_id"]

    if Accounts.guardian_has_access?(guardian_id, student_id) do
      attrs
      |> normalize_keys()
      |> Map.merge(%{
        "guardian_id" => guardian_id,
        "proposed_by" => "guardian",
        "status" => "proposed"
      })
      |> Map.put_new("start_date", Date.utc_today())
      |> insert_goal()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Student (or, for student-proposed goals, the guardian) accepts a
  proposed goal, flipping it to `:active` with an `accepted_at` stamp.
  """
  def accept_goal(goal_id, actor_role) when actor_role in [:student, :guardian] do
    case Repo.get(StudyGoal, goal_id) do
      nil ->
        {:error, :not_found}

      %StudyGoal{status: :proposed, proposed_by: proposed_by} = goal
      when proposed_by != actor_role ->
        update_goal(goal, %{
          status: :active,
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      %StudyGoal{status: :proposed} ->
        {:error, :cannot_accept_own_proposal}

      %StudyGoal{} ->
        {:error, :not_proposed}
    end
  end

  @doc """
  Counter-proposes a goal: creates a new `:proposed` goal from the
  counter-party (the spec's design-principle #3 translation of Grolnick's
  autonomy-supportive involvement finding), and marks the original as
  `:abandoned` so it stops cluttering the list.
  """
  def counter_goal(goal_id, actor_role, new_attrs)
      when actor_role in [:student, :guardian] and is_map(new_attrs) do
    case Repo.get(StudyGoal, goal_id) do
      nil ->
        {:error, :not_found}

      %StudyGoal{status: :proposed, proposed_by: proposed_by} = original
      when proposed_by != actor_role ->
        do_counter(original, actor_role, new_attrs)

      %StudyGoal{status: :proposed} ->
        {:error, :cannot_counter_own_proposal}

      %StudyGoal{} ->
        {:error, :not_proposed}
    end
  end

  defp do_counter(%StudyGoal{} = original, actor_role, new_attrs) do
    Repo.transaction(fn ->
      {:ok, _} = update_goal(original, %{status: :abandoned})

      case insert_goal(counter_attrs(original, actor_role, new_attrs)) do
        {:ok, g} -> g
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp counter_attrs(%StudyGoal{} = original, actor_role, new_attrs) do
    original
    |> Map.from_struct()
    |> Map.take([:student_id, :guardian_id, :course_id, :test_schedule_id, :goal_type])
    |> normalize_keys()
    |> Map.merge(normalize_keys(new_attrs))
    |> Map.merge(%{
      "proposed_by" => Atom.to_string(actor_role),
      "status" => "proposed"
    })
    |> Map.put_new("start_date", Date.utc_today())
  end

  @doc """
  Declines a proposed goal with an optional reason. Marks it `:abandoned`
  so history is preserved but the goal is no longer active.
  """
  def decline_goal(goal_id, actor_role, reason \\ nil)
      when actor_role in [:student, :guardian] do
    case Repo.get(StudyGoal, goal_id) do
      nil ->
        {:error, :not_found}

      %StudyGoal{status: :proposed, proposed_by: proposed_by} = goal
      when proposed_by != actor_role ->
        update_goal(goal, %{status: :abandoned, decline_reason: reason})

      %StudyGoal{status: :proposed} ->
        {:error, :cannot_decline_own_proposal}

      %StudyGoal{} ->
        {:error, :not_proposed}
    end
  end

  @doc "Marks an active goal as achieved. Used to trigger the Phase 3 share CTA."
  def mark_goal_achieved(%StudyGoal{status: :active} = goal) do
    update_goal(goal, %{status: :achieved})
  end

  def mark_goal_achieved(_), do: {:error, :not_active}

  @doc "All goals for a student, most recent first."
  def list_goals_for_student(student_id) when is_binary(student_id) do
    from(g in StudyGoal,
      where: g.student_id == ^student_id,
      order_by: [desc: g.inserted_at]
    )
    |> Repo.all()
  end

  @doc "All `:active` goals for a student."
  def list_active_goals(student_id) when is_binary(student_id) do
    from(g in StudyGoal,
      where: g.student_id == ^student_id and g.status == :active,
      order_by: [asc: g.end_date]
    )
    |> Repo.all()
  end

  @doc "All `:proposed` goals awaiting action, filtered by who must act next."
  def list_pending_for(role, user_role_id)
      when role in [:student, :guardian] and is_binary(user_role_id) do
    field = if role == :student, do: :student_id, else: :guardian_id
    other_role = if role == :student, do: :guardian, else: :student

    from(g in StudyGoal,
      where:
        field(g, ^field) == ^user_role_id and
          g.status == :proposed and
          g.proposed_by == ^other_role,
      order_by: [desc: g.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns real progress toward the given active goal.

  Daily-minutes and weekly-practice-count goals consult `study_sessions`.
  Streak goals consult `Gamification`. Target-readiness goals defer to
  the forecaster / latest readiness — caller should supply the readiness
  snapshot if they have one cached.

  Never fabricated. Returns `%{status: :insufficient_data}` when we can't
  compute the metric yet.
  """
  def goal_progress(%StudyGoal{status: :active} = goal) do
    case goal.goal_type do
      :daily_minutes -> daily_minutes_progress(goal)
      :weekly_practice_count -> weekly_practice_progress(goal)
      :streak_days -> streak_progress(goal)
      :target_readiness_score -> %{status: :insufficient_data, reason: :use_forecaster}
    end
  end

  def goal_progress(_), do: %{status: :not_active}

  defp daily_minutes_progress(goal) do
    today = Date.utc_today()
    since = goal.start_date
    days_elapsed = max(Date.diff(today, since), 1)

    minutes =
      from(s in FunSheep.Engagement.StudySession,
        where:
          s.user_role_id == ^goal.student_id and
            not is_nil(s.completed_at) and
            fragment("?::date", s.completed_at) >= ^since,
        select: coalesce(sum(s.duration_seconds), 0)
      )
      |> Repo.one()
      |> div(60)

    actual_daily = div(minutes, days_elapsed)
    on_track? = actual_daily >= goal.target_value

    %{
      status: :ok,
      actual_daily_minutes: actual_daily,
      target_daily_minutes: goal.target_value,
      on_track?: on_track?,
      adherence_pct: adherence_pct(actual_daily, goal.target_value),
      days_elapsed: days_elapsed,
      minutes_total: minutes
    }
  end

  defp weekly_practice_progress(goal) do
    today = Date.utc_today()
    since = goal.start_date
    weeks_elapsed = max(Float.round(Date.diff(today, since) / 7, 2), 0.5)

    count =
      from(s in FunSheep.Engagement.StudySession,
        where:
          s.user_role_id == ^goal.student_id and
            s.session_type in ["practice", "quick_test"] and
            not is_nil(s.completed_at) and
            fragment("?::date", s.completed_at) >= ^since,
        select: count(s.id)
      )
      |> Repo.one()

    actual_per_week = Float.round(count / weeks_elapsed, 2)

    %{
      status: :ok,
      actual_per_week: actual_per_week,
      target_per_week: goal.target_value,
      on_track?: actual_per_week >= goal.target_value,
      adherence_pct: adherence_pct(actual_per_week, goal.target_value),
      weeks_elapsed: weeks_elapsed,
      sessions_total: count
    }
  end

  defp streak_progress(goal) do
    streak =
      case Gamification.get_or_create_streak(goal.student_id) do
        {:ok, %{current_streak: n}} -> n
        _ -> 0
      end

    %{
      status: :ok,
      current_streak: streak,
      target_streak: goal.target_value,
      on_track?: streak >= goal.target_value,
      adherence_pct: adherence_pct(streak, goal.target_value)
    }
  end

  defp adherence_pct(actual, target) when is_number(actual) and is_number(target) and target > 0,
    do: min(100, round(actual / target * 100))

  defp adherence_pct(_, _), do: 0

  ## ── Practice Assignments (§7.2) ──────────────────────────────────────────

  @doc """
  Parent assigns bounded practice on a topic (section). Enforces the two
  caps that keep the feature from becoming a weapon:

    * at most `#{@max_open_assignments_per_student}` open assignments per
      student
    * at most #{PracticeAssignment.max_questions()} questions per
      assignment

  The parent must be an active guardian of the student.
  """
  def assign_practice(guardian_id, student_id, section_id, opts \\ [])
      when is_binary(guardian_id) and is_binary(student_id) do
    with true <- Accounts.guardian_has_access?(guardian_id, student_id),
         :ok <- check_open_assignment_cap(student_id),
         {:ok, count} <-
           clamp_question_count(Keyword.get(opts, :question_count, @default_practice_questions)),
         {:ok, section_ctx} <- resolve_section(section_id) do
      attrs = %{
        guardian_id: guardian_id,
        student_id: student_id,
        section_id: section_ctx.section_id,
        chapter_id: section_ctx.chapter_id,
        course_id: section_ctx.course_id,
        question_count: count,
        due_date:
          Keyword.get(opts, :due_date, Date.add(Date.utc_today(), @default_assignment_due_days)),
        status: :pending
      }

      %PracticeAssignment{}
      |> PracticeAssignment.changeset(attrs)
      |> Repo.insert()
    else
      false -> {:error, :unauthorized}
      other -> other
    end
  end

  defp check_open_assignment_cap(student_id) do
    count =
      from(a in PracticeAssignment,
        where:
          a.student_id == ^student_id and
            a.status in [:pending, :in_progress],
        select: count(a.id)
      )
      |> Repo.one()

    if count < @max_open_assignments_per_student do
      :ok
    else
      {:error, :too_many_open_assignments}
    end
  end

  defp clamp_question_count(count) when is_integer(count) and count > 0 do
    if count <= PracticeAssignment.max_questions() do
      {:ok, count}
    else
      {:error, :too_many_questions}
    end
  end

  defp clamp_question_count(_), do: {:error, :invalid_question_count}

  defp resolve_section(section_id) do
    case FunSheep.Courses.get_section(section_id) do
      nil ->
        {:error, :section_not_found}

      section ->
        case FunSheep.Courses.get_chapter(section.chapter_id) do
          nil ->
            {:error, :chapter_not_found}

          chapter ->
            {:ok,
             %{
               section_id: section.id,
               chapter_id: chapter.id,
               course_id: chapter.course_id
             }}
        end
    end
  end

  @doc "Lists open (pending / in_progress) assignments for a student."
  def list_open_assignments(student_id) when is_binary(student_id) do
    from(a in PracticeAssignment,
      where: a.student_id == ^student_id and a.status in [:pending, :in_progress],
      order_by: [asc: a.due_date],
      preload: [:section, :chapter]
    )
    |> Repo.all()
  end

  @doc "All assignments for a student regardless of status, newest first."
  def list_assignments_for_student(student_id) when is_binary(student_id) do
    from(a in PracticeAssignment,
      where: a.student_id == ^student_id,
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Marks an assignment complete and records real accuracy numbers."
  def complete_assignment(%PracticeAssignment{status: status} = assignment, attempted, correct)
      when status in [:pending, :in_progress] and is_integer(attempted) and is_integer(correct) do
    assignment
    |> PracticeAssignment.changeset(%{
      status: :completed,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      questions_attempted: attempted,
      questions_correct: correct
    })
    |> Repo.update()
  end

  def complete_assignment(_, _, _), do: {:error, :not_open}

  @doc """
  Sweeps assignments whose due_date is in the past and marks them `:expired`.
  Intended to be called from a daily Oban worker (Phase 4).
  """
  def expire_past_due_assignments(today \\ Date.utc_today()) do
    from(a in PracticeAssignment,
      where: a.status in [:pending, :in_progress] and a.due_date < ^today
    )
    |> Repo.update_all(
      set: [status: :expired, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )
  end

  ## ── Conversation Prompts (§7.3) ─────────────────────────────────────────

  @doc """
  Returns a list of conversation-prompt cards for a parent to use this
  week. Each card is parameterised with real goal-adherence data. Never
  auto-sent to the student — these are scripts for the parent.

  Returns `[]` (no prompt) when there's nothing real to say. No filler.
  """
  def conversation_prompts_for_parent(guardian_id, student_id)
      when is_binary(guardian_id) and is_binary(student_id) do
    if Accounts.guardian_has_access?(guardian_id, student_id) do
      active = list_active_goals(student_id)
      Enum.flat_map(active, &goal_to_prompt(&1, student_id))
    else
      []
    end
  end

  defp goal_to_prompt(%StudyGoal{goal_type: :daily_minutes} = goal, student_id) do
    progress = daily_minutes_progress(goal)

    if progress.status == :ok and not progress.on_track? and progress.days_elapsed >= 3 do
      [
        %{
          kind: :missed_sessions,
          goal_id: goal.id,
          student_id: student_id,
          summary:
            "has averaged #{progress.actual_daily_minutes} min/day vs. a #{goal.target_value}-min goal",
          opener: "What's been hardest about getting started this week?",
          rationale:
            "Open questions outperform directives when scheduling friction — not motivation — is the issue."
        }
      ]
    else
      []
    end
  end

  defp goal_to_prompt(%StudyGoal{goal_type: :streak_days} = goal, student_id) do
    streak =
      case Gamification.get_or_create_streak(student_id) do
        {:ok, %{current_streak: n}} -> n
        _ -> 0
      end

    if streak == 0 do
      [
        %{
          kind: :streak_broken,
          goal_id: goal.id,
          student_id: student_id,
          summary: "streak has reset and a short restart often beats a long session",
          opener: "Want to try a 10-minute warm-up together later?",
          rationale: "Lower-friction re-entry is a known habit-recovery lever."
        }
      ]
    else
      []
    end
  end

  defp goal_to_prompt(_, _), do: []

  ## ── Peer-sharing Triggers (parent-initiated share) ───────────────────────

  @doc """
  Returns share-CTA triggers for the parent. Only fires on real achievement
  moments — goal achieved, target hit. No auto-sharing: the parent still
  clicks the existing `/share/progress/:token` flow.
  """
  def share_triggers(guardian_id, student_id)
      when is_binary(guardian_id) and is_binary(student_id) do
    if Accounts.guardian_has_access?(guardian_id, student_id) do
      goal_triggers(student_id)
    else
      []
    end
  end

  defp goal_triggers(student_id) do
    from(g in StudyGoal,
      where:
        g.student_id == ^student_id and
          g.status == :achieved and
          g.updated_at >= ago(7, "day"),
      order_by: [desc: g.updated_at]
    )
    |> Repo.all()
    |> Enum.map(fn g ->
      %{
        kind: :goal_achieved,
        goal_id: g.id,
        goal_type: g.goal_type,
        target_value: g.target_value,
        achieved_at: g.updated_at
      }
    end)
  end

  ## ── Private helpers ──────────────────────────────────────────────────────

  defp insert_goal(attrs) do
    %StudyGoal{}
    |> StudyGoal.changeset(attrs)
    |> Repo.insert()
  end

  defp update_goal(%StudyGoal{} = goal, attrs) do
    goal
    |> StudyGoal.changeset(attrs)
    |> Repo.update()
  end

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
