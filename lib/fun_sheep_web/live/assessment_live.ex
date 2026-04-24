defmodule FunSheepWeb.AssessmentLive do
  use FunSheepWeb, :live_view

  import FunSheepWeb.BillingComponents
  import FunSheepWeb.ProgressPanel, only: [panel: 1]

  alias FunSheep.{Assessments, Billing, Courses, Engagement, Gamification, Progress, Questions}
  alias FunSheep.Assessments.{Engine, SessionStore, StateCache}
  alias FunSheep.Gamification.FpEconomy
  alias FunSheep.Progress.Event, as: ProgressEvent
  alias FunSheep.Questions.FreeformGrader

  require Logger

  @xp_per_correct FpEconomy.xp_per_correct()

  @impl true
  def mount(%{"course_id" => course_id, "schedule_id" => schedule_id}, _session, socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    role = socket.assigns.current_user["role"]
    schedule = Assessments.get_test_schedule_with_course!(schedule_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(FunSheep.PubSub, "course:#{course_id}")
      Progress.subscribe(:course, course_id)
    end

    # On reconnect, try ETS cache first, then DB, before treating as fresh start
    case StateCache.get(user_role_id, schedule_id) do
      {:ok, cached} ->
        {:ok, restore_from_cache(socket, course_id, schedule, cached)}

      :miss ->
        case SessionStore.load(user_role_id, schedule_id) do
          {:ok, persisted} ->
            # Warm ETS from DB so future reconnects within the same run hit ETS
            StateCache.put(user_role_id, schedule_id, persisted)
            socket = restore_from_cache(socket, course_id, schedule, persisted)

            # After a server restart, current_question is nil; advance the engine
            # so the student sees the next question rather than a blank screen.
            socket =
              if persisted.phase == :testing and is_nil(persisted[:current_question]) and
                   not is_nil(persisted[:engine_state]) do
                socket
                |> advance_to_next_question()
                |> save_state_to_cache()
              else
                socket
              end

            {:ok, socket}

          :miss ->
            mount_fresh(socket, user_role_id, role, course_id, schedule)
        end
    end
  end

  defp mount_fresh(socket, user_role_id, role, course_id, schedule) do
    case Billing.check_test_allowance(user_role_id, role) do
      :ok ->
        Billing.record_test_usage(user_role_id, "assessment", course_id)
        mount_assessment(socket, course_id, schedule)

      {:error, :limit_reached, _info} ->
        billing_stats = Billing.usage_stats(user_role_id)

        socket =
          socket
          |> assign(
            page_title: "Assessment: #{schedule.name}",
            course_id: course_id,
            schedule: schedule,
            billing_blocked: true,
            billing_stats: billing_stats,
            engine_state: nil,
            current_question: nil,
            selected_answer: nil,
            feedback: nil,
            question_number: 0,
            start_time: 0,
            phase: :blocked,
            readiness: nil,
            generation_progress: %{},
            grading: false,
            grading_task: nil
          )

        {:ok, socket}
    end
  end

  defp restore_from_cache(socket, course_id, schedule, cached) do
    # Always re-derive question_types from the current format_template so that:
    # (a) stale cached states (from before question_types was added) get the
    #     filter applied, and (b) if the teacher updates the format template the
    #     next reconnect picks it up.
    engine_state =
      case cached.engine_state do
        nil ->
          nil

        state ->
          question_types = Engine.format_question_types(schedule.format_template)
          Map.put(state, :question_types, question_types)
      end

    socket
    |> assign(
      page_title: "Assessment: #{schedule.name}",
      course_id: course_id,
      schedule: schedule,
      billing_blocked: false,
      billing_stats: nil,
      engine_state: engine_state,
      current_question: cached.current_question,
      current_question_stats: cached.current_question_stats,
      selected_answer: cached.selected_answer,
      feedback: cached.feedback,
      question_number: cached.question_number,
      start_time: System.monotonic_time(:second),
      assessment_complete: cached.assessment_complete,
      summary: cached.summary,
      phase: cached.phase,
      readiness: nil,
      generation_progress: %{},
      grading: false,
      grading_task: nil
    )
  end

  defp mount_assessment(socket, course_id, schedule) do
    readiness = Assessments.scope_readiness(schedule)

    # Route to one of two top-level phases:
    #   :readiness_block — upstream pipeline hasn't produced enough visible
    #                      questions for this scope; no point entering the
    #                      engine yet.
    #   :testing        — engine kicks off immediately on the test's scope.
    #
    # There is no source-picker phase: assessment runs on the full set of
    # questions matching the test's chapter scope. Source attribution
    # (which uploaded file a question came from) is not a student concern.
    initial_phase =
      case readiness do
        :ready -> :testing
        {:scope_partial, _} -> :testing
        _ -> :readiness_block
      end

    socket =
      socket
      |> assign(
        page_title: "Assessment: #{schedule.name}",
        course_id: course_id,
        schedule: schedule,
        billing_blocked: false,
        billing_stats: nil,
        engine_state: nil,
        current_question: nil,
        selected_answer: nil,
        feedback: nil,
        question_number: 0,
        start_time: System.monotonic_time(:second),
        phase: initial_phase,
        readiness: readiness,
        generation_progress: %{},
        grading: false,
        grading_task: nil
      )

    socket =
      if initial_phase == :testing do
        state = Engine.start_assessment(schedule)

        socket
        |> assign(engine_state: state)
        |> advance_to_next_question()
        |> save_state_to_cache()
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("select_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("update_text_answer", %{"answer" => answer}, socket) do
    {:noreply, assign(socket, selected_answer: answer)}
  end

  def handle_event("submit_answer", _params, socket) do
    %{
      current_question: question,
      selected_answer: answer,
      engine_state: state,
      start_time: start_time
    } = socket.assigns

    if answer == nil or question == nil do
      {:noreply, socket}
    else
      freeform? = question.question_type in [:short_answer, :free_response]

      if freeform? do
        task = Task.async(fn -> FreeformGrader.grade(question, answer) end)

        {:noreply,
         socket
         |> assign(grading: true, grading_task: task.ref)}
      else
        is_correct = check_answer(question, answer)

        socket =
          apply_grading_result(socket, question, answer, state, start_time, is_correct, nil)

        {:noreply, socket}
      end
    end
  end

  def handle_event("next_question", _params, socket) do
    socket =
      socket
      |> assign(feedback: nil, selected_answer: nil)
      |> advance_to_next_question()
      |> save_state_to_cache()

    {:noreply, socket}
  end

  # Student clicked "Generate now" on the readiness-block screen. Re-enqueue
  # generation for every chapter still below threshold. Idempotent — the
  # worker's Oban uniqueness (5-min window) collapses duplicates. Seed a
  # :queued progress event per chapter immediately so the UI shows real-time,
  # named feedback from click to completion (see
  # .claude/rules/i/progress-feedback.md).
  def handle_event("retry_generation", _params, socket) do
    course_id = socket.assigns.course_id
    queued_ids = Assessments.ensure_generation_queued(socket.assigns.schedule)
    chapters = Courses.list_chapters_by_ids(queued_ids)

    seeded =
      Map.new(chapters, fn chapter ->
        {chapter.id,
         ProgressEvent.new(
           job_id: "chapter:#{chapter.id}",
           topic_type: :course,
           topic_id: course_id,
           scope: :question_regeneration,
           phase_total: 3,
           subject_id: chapter.id,
           subject_label: chapter.name
         )}
      end)

    # Merge: keep existing in-flight entries (don't clobber a running event
    # with a fresh :queued one); add new ones for chapters not yet tracked.
    merged_progress =
      Map.merge(seeded, socket.assigns.generation_progress, fn _id, new, existing ->
        if ProgressEvent.terminal?(existing), do: new, else: existing
      end)

    flash =
      if queued_ids == [] and socket.assigns.generation_progress == %{} do
        "Already queued — questions will appear here as soon as they're ready."
      else
        nil
      end

    socket = assign(socket, generation_progress: merged_progress)
    socket = if flash, do: put_flash(socket, :info, flash), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {:ok, %{correct: is_correct, feedback: ai_feedback}}}, socket)
      when socket.assigns.grading_task == ref do
    Process.demonitor(ref, [:flush])

    %{
      current_question: question,
      selected_answer: answer,
      engine_state: state,
      start_time: start_time
    } = socket.assigns

    socket =
      socket
      |> assign(grading: false, grading_task: nil)
      |> apply_grading_result(question, answer, state, start_time, is_correct, ai_feedback)

    {:noreply, socket}
  end

  def handle_info({ref, {:error, _reason}}, socket)
      when socket.assigns.grading_task == ref do
    Process.demonitor(ref, [:flush])

    %{
      current_question: question,
      selected_answer: answer,
      engine_state: state,
      start_time: start_time
    } = socket.assigns

    is_correct = check_answer(question, answer)

    socket =
      socket
      |> assign(grading: false, grading_task: nil)
      |> apply_grading_result(question, answer, state, start_time, is_correct, nil)

    {:noreply, socket}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when socket.assigns.grading_task == ref do
    %{
      current_question: question,
      selected_answer: answer,
      engine_state: state,
      start_time: start_time
    } = socket.assigns

    is_correct = check_answer(question, answer)

    socket =
      socket
      |> assign(grading: false, grading_task: nil)
      |> apply_grading_result(question, answer, state, start_time, is_correct, nil)

    {:noreply, socket}
  end

  # Course-level pipeline event: discovery/OCR/generation/validation all
  # broadcast `{:processing_update, ...}` on `course:{id}`. Any such event
  # might have just tipped the scope into `:ready`; re-check and transition
  # if so. No-op when the assessment is already underway (`phase == :testing`
  # with an engine state) — we don't want a late broadcast to boot the
  # student out of an in-flight question.
  def handle_info({:processing_update, _data}, socket) do
    {:noreply, maybe_transition_on_readiness(socket)}
  end

  # Finer-grained per-chapter signal emitted by
  # `QuestionValidationWorker`/`QuestionClassificationWorker` whenever a
  # question transitions into student-visible + adaptive-eligible.
  def handle_info({:questions_ready, %{chapter_ids: _ids}}, socket) do
    {:noreply, maybe_transition_on_readiness(socket)}
  end

  # Real-time regeneration progress. Each chapter is keyed separately so the
  # panel can render concurrent chapters as independent rows with their own
  # phase/progress state. See .claude/rules/i/progress-feedback.md.
  def handle_info({:progress, %ProgressEvent{scope: :question_regeneration} = event}, socket) do
    key = event.subject_id || event.job_id
    updated = Map.put(socket.assigns.generation_progress, key, event)
    {:noreply, assign(socket, generation_progress: updated)}
  end

  def handle_info({:progress, _event}, socket), do: {:noreply, socket}

  def handle_info(_other, socket), do: {:noreply, socket}

  defp apply_grading_result(socket, question, answer, state, start_time, is_correct, ai_feedback) do
    time_taken = System.monotonic_time(:second) - start_time
    user_role_id = socket.assigns.current_user["user_role_id"]

    if user_role_id do
      Questions.record_attempt_with_stats(%{
        user_role_id: user_role_id,
        question_id: question.id,
        answer_given: answer,
        is_correct: is_correct,
        time_taken_seconds: max(time_taken, 0),
        difficulty_at_attempt: to_string(state.current_difficulty)
      })

      if is_correct do
        Gamification.award_xp(user_role_id, @xp_per_correct, "assessment", source_id: question.id)
      end

      Gamification.record_activity(user_role_id)
    end

    new_state = Engine.record_answer(state, question.id, answer, is_correct)

    socket
    |> assign(
      engine_state: new_state,
      feedback: %{
        is_correct: is_correct,
        correct_answer: question.answer,
        ai_feedback: ai_feedback
      }
    )
    |> save_state_to_cache()
  end

  defp maybe_transition_on_readiness(%{assigns: %{phase: :readiness_block}} = socket) do
    readiness = Assessments.scope_readiness(socket.assigns.schedule)

    can_start = readiness == :ready or match?({:scope_partial, _}, readiness)

    cond do
      can_start ->
        state = Engine.start_assessment(socket.assigns.schedule)

        socket
        |> assign(engine_state: state, phase: :testing, readiness: readiness)
        |> advance_to_next_question()
        |> save_state_to_cache()

      true ->
        # Still blocked, but the specific sub-state may have changed
        # (e.g., `:course_not_ready` → `:scope_partial`). Refresh the assign
        # so the UI updates its messaging.
        assign(socket, readiness: readiness)
    end
  end

  defp maybe_transition_on_readiness(socket), do: socket

  defp advance_to_next_question(socket) do
    state = socket.assigns.engine_state

    case Engine.next_question(state) do
      {:question, question, new_state} ->
        # Load community stats for this question
        question_stats = Questions.get_question_stats(question.id)

        assign(socket,
          engine_state: new_state,
          current_question: question,
          current_question_stats: question_stats,
          question_number: socket.assigns.question_number + 1,
          start_time: System.monotonic_time(:second)
        )

      {:complete, new_state} ->
        summary = Engine.summary(new_state)
        previous_aggregate = snapshot_and_fetch_previous(socket)
        finalize_session(socket)

        assign(socket,
          engine_state: new_state,
          current_question: nil,
          assessment_complete: true,
          summary: summary,
          previous_aggregate_score: previous_aggregate
        )

      {:no_questions_available, new_state} ->
        assign(socket,
          engine_state: new_state,
          current_question: nil,
          assessment_complete: false,
          no_questions_available: true,
          summary: nil
        )

      _other ->
        # generate_needed or other - treat as complete for now
        summary = Engine.summary(state)
        previous_aggregate = snapshot_and_fetch_previous(socket)
        finalize_session(socket)

        assign(socket,
          current_question: nil,
          assessment_complete: true,
          summary: summary,
          previous_aggregate_score: previous_aggregate
        )
    end
  end

  # Teacher-review fix #6: snapshot the current readiness and return the
  # prior score (if any) so the summary screen can show the retake delta.
  # Readiness history was only written from the dashboard before — moving
  # the write here means every assessment completion persists a data point,
  # which is what makes "again-and-again until 100% ready" measurable.
  defp snapshot_and_fetch_previous(socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule_id = socket.assigns.schedule.id

    if user_role_id && schedule_id do
      # History BEFORE we snapshot the current run — the most recent entry
      # is the score from the prior completion (or nil on first run).
      previous =
        case Assessments.list_readiness_history(user_role_id, schedule_id, 1) do
          [%{aggregate_score: score} | _] when is_float(score) or is_integer(score) -> score
          _ -> nil
        end

      case Assessments.calculate_and_save_readiness(user_role_id, schedule_id) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("readiness snapshot failed: #{inspect(reason)}")
      end

      previous
    end
  end

  defp finalize_session(socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    course_id = socket.assigns.schedule.course_id

    if user_role_id && course_id do
      Engagement.after_session(user_role_id, course_id)
    end

    :ok
  end

  defp save_state_to_cache(socket) do
    user_role_id = socket.assigns.current_user["user_role_id"]
    schedule_id = socket.assigns.schedule.id
    assessment_complete = Map.get(socket.assigns, :assessment_complete, false)
    no_questions_available = Map.get(socket.assigns, :no_questions_available, false)

    if assessment_complete or no_questions_available do
      StateCache.delete(user_role_id, schedule_id)
      SessionStore.delete(user_role_id, schedule_id)
    else
      state = %{
        engine_state: socket.assigns.engine_state,
        current_question: socket.assigns.current_question,
        current_question_stats: Map.get(socket.assigns, :current_question_stats),
        selected_answer: socket.assigns.selected_answer,
        feedback: socket.assigns.feedback,
        question_number: socket.assigns.question_number,
        assessment_complete: assessment_complete,
        summary: Map.get(socket.assigns, :summary),
        phase: socket.assigns.phase
      }

      StateCache.put(user_role_id, schedule_id, state)
      SessionStore.save(user_role_id, schedule_id, state)
    end

    socket
  end

  defp check_answer(question, answer), do: FunSheep.Questions.Grading.correct?(question, answer)

  defp difficulty_badge_class(difficulty) do
    case difficulty do
      :easy -> "bg-[#E8F8EB] text-[#4CD964]"
      :medium -> "bg-yellow-100 text-yellow-700"
      :hard -> "bg-red-100 text-[#FF3B30]"
    end
  end

  defp difficulty_label(difficulty) do
    case difficulty do
      :easy -> "Easy"
      :medium -> "Medium"
      :hard -> "Hard"
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Map.put_new(:assessment_complete, false)
      |> Map.put_new(:no_questions_available, false)
      |> Map.put_new(:summary, nil)
      |> Map.put_new(:readiness, nil)
      |> Map.put_new(:generation_progress, %{})

    ~H"""
    <div class="max-w-3xl mx-auto">
      <.billing_wall
        :if={@billing_blocked}
        course_id={@course_id}
        course_name={@schedule.course.name}
        stats={@billing_stats}
      />

      <div :if={!@billing_blocked}>
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-4">
            <button
              type="button"
              onclick="history.back()"
              class="text-[#8E8E93] hover:text-[#1C1C1E] transition-colors cursor-pointer"
              aria-label="Go back"
            >
              <.icon name="hero-arrow-left" class="w-6 h-6" />
            </button>
            <div>
              <h1 class="text-2xl font-bold text-[#1C1C1E]">{@schedule.name}</h1>
              <p class="text-sm text-[#8E8E93]">{@schedule.course.name}</p>
            </div>
          </div>

          <div
            :if={@phase == :testing && !@assessment_complete && @engine_state}
            class="flex items-center gap-4"
          >
            <span class={"px-3 py-1 rounded-full text-xs font-medium #{difficulty_badge_class(@engine_state.current_difficulty)}"}>
              {difficulty_label(@engine_state.current_difficulty)}
            </span>
          </div>
        </div>

        <%= cond do %>
          <% @phase == :readiness_block -> %>
            <.render_generation_progress
              :if={map_size(@generation_progress) > 0}
              progress={@generation_progress}
            />
            <.render_readiness_block
              :if={not all_terminal_success?(@generation_progress)}
              readiness={@readiness}
              schedule={@schedule}
              course_id={@course_id}
              has_progress?={map_size(@generation_progress) > 0}
            />
            <div
              :if={all_terminal_success?(@generation_progress)}
              class="bg-white rounded-2xl shadow-md p-6 mt-4 text-center"
            >
              <p class="text-sm text-[#8E8E93]">
                Questions are being validated. This screen will refresh automatically once they're ready.
              </p>
            </div>
          <% @no_questions_available -> %>
            <.render_no_questions schedule={@schedule} course_id={@course_id} />
          <% @assessment_complete -> %>
            <.render_summary
              summary={@summary}
              schedule={@schedule}
              previous_aggregate_score={assigns[:previous_aggregate_score]}
            />
          <% true -> %>
            <.render_question
              question={@current_question}
              selected_answer={@selected_answer}
              feedback={@feedback}
              question_number={@question_number}
              engine_state={@engine_state}
              question_stats={assigns[:current_question_stats]}
              grading={assigns[:grading] || false}
            />
        <% end %>
      </div>
    </div>
    """
  end

  attr :readiness, :any, required: true
  attr :schedule, :map, required: true
  attr :course_id, :string, required: true
  attr :has_progress?, :boolean, default: false

  defp render_readiness_block(assigns) do
    copy = readiness_copy(assigns.readiness)
    retry_chapter_count = retry_chapter_count(assigns.readiness)

    assigns =
      assign(assigns,
        heading: copy.heading,
        body: copy.body,
        tone: copy.tone,
        show_retry?: copy.show_retry?,
        retry_chapter_count: retry_chapter_count
      )

    ~H"""
    <div class={[
      "bg-white rounded-2xl shadow-md p-8 text-center",
      if(@has_progress?, do: "mt-4", else: "")
    ]}>
      <.icon
        name={readiness_icon(@tone)}
        class={"w-16 h-16 mx-auto mb-4 #{readiness_icon_class(@tone)}"}
      />
      <h2 class="text-2xl font-bold text-[#1C1C1E]">{@heading}</h2>
      <p class="text-[#8E8E93] mt-3 max-w-md mx-auto">{@body}</p>
      <div
        :if={@show_retry? and @retry_chapter_count > 0 and not @has_progress?}
        class="mt-4 text-sm text-[#8E8E93]"
      >
        {@retry_chapter_count} chapter{if @retry_chapter_count != 1, do: "s"} will generate questions now.
      </div>
      <div class="flex justify-center gap-3 mt-6">
        <.link
          navigate={~p"/courses/#{@course_id}"}
          class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
        >
          Go to Course Page
        </.link>
        <button
          :if={@show_retry? and not @has_progress?}
          phx-click="retry_generation"
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Generate Questions Now
        </button>
      </div>
    </div>
    """
  end

  attr :progress, :map, required: true

  defp render_generation_progress(assigns) do
    events =
      assigns.progress
      |> Map.values()
      |> Enum.sort_by(&{&1.status != :running, &1.subject_label || ""})

    running_count = Enum.count(events, fn e -> e.status in [:queued, :running] end)
    total = length(events)

    subtitle =
      cond do
        running_count > 0 ->
          "Working on #{running_count} chapter#{if running_count == 1, do: "", else: "s"} — " <>
            "each takes about a minute. You can leave this page; progress keeps going."

        true ->
          "All chapters processed."
      end

    assigns =
      assign(assigns,
        events: events,
        title: "Regenerating questions · #{total} chapter#{if total == 1, do: "", else: "s"}",
        subtitle: subtitle
      )

    ~H"""
    <.panel title={@title} subtitle={@subtitle} events={@events} />
    """
  end

  # Readiness → UI copy. Each branch of `ScopeReadiness.check/1` has a
  # distinct message so the student knows *why* they're blocked and what to
  # do next — instead of the old catch-all "Questions not ready yet".
  defp readiness_copy({:course_not_ready, stage}) do
    %{
      heading: "Course is still processing",
      body:
        "Your course is still being built (#{humanize_stage(stage)}). " <>
          "Questions will be ready as soon as processing finishes — usually a few minutes.",
      tone: :info,
      show_retry?: false
    }
  end

  defp readiness_copy({:course_failed, reason}) do
    detail =
      case reason do
        r when is_binary(r) and r != "" -> " " <> r
        _ -> ""
      end

    %{
      heading: "Course processing failed",
      body:
        "We couldn't finish building this course.#{detail} " <>
          "Open the course page to retry or contact support.",
      tone: :error,
      show_retry?: false
    }
  end

  defp readiness_copy({:scope_empty, _chapter_ids}) do
    %{
      heading: "No questions for the selected chapters",
      body:
        "None of the chapters assigned to this test have questions yet. " <>
          "You can generate them now — it usually takes a few minutes.",
      tone: :warning,
      show_retry?: true
    }
  end

  defp readiness_copy({:scope_partial, %{missing: missing}}) do
    count = length(missing)

    %{
      heading: "Some chapters still need questions",
      body:
        "#{count} of the chapters in this test don't have enough questions yet. " <>
          "You can generate more now, or start with what's ready.",
      tone: :warning,
      show_retry?: true
    }
  end

  defp readiness_copy(_other) do
    # Should never fire for `:ready` (we wouldn't be rendering this block).
    # Kept as a safety net so unexpected shapes still show an honest message.
    %{
      heading: "Questions not ready yet",
      body: "We're preparing your questions. Please check back in a few minutes.",
      tone: :info,
      show_retry?: true
    }
  end

  defp retry_chapter_count({:scope_empty, ids}), do: length(ids)
  defp retry_chapter_count({:scope_partial, %{missing: missing}}), do: length(missing)
  defp retry_chapter_count(_), do: 0

  # True when at least one progress entry exists and every entry is in the
  # :succeeded terminal state. Used to swap the readiness-block copy for a
  # "validating" interstitial, since the stale "no questions yet" wording
  # contradicts what the progress panel is showing.
  defp all_terminal_success?(progress) when map_size(progress) == 0, do: false

  defp all_terminal_success?(progress) do
    Enum.all?(progress, fn {_k, %{status: s}} -> s == :succeeded end)
  end

  defp readiness_icon(:error), do: "hero-exclamation-triangle"
  defp readiness_icon(:warning), do: "hero-clock"
  defp readiness_icon(_), do: "hero-clock"

  defp readiness_icon_class(:error), do: "text-[#FF3B30]"
  defp readiness_icon_class(:warning), do: "text-[#FFCC00]"
  defp readiness_icon_class(_), do: "text-[#4CD964]"

  defp humanize_stage(:pending), do: "queued"
  defp humanize_stage(:processing), do: "starting up"
  defp humanize_stage(:discovering), do: "discovering chapters"
  defp humanize_stage(:extracting), do: "extracting questions from your materials"
  defp humanize_stage(:generating), do: "generating questions"
  defp humanize_stage(:validating), do: "validating questions"
  defp humanize_stage(_other), do: "processing"

  attr :schedule, :map, required: true
  attr :course_id, :string, required: true

  defp render_no_questions(assigns) do
    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-8 text-center">
      <.icon name="hero-clock" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
      <h2 class="text-2xl font-bold text-[#1C1C1E]">Questions not ready yet</h2>
      <p class="text-[#8E8E93] mt-3 max-w-md mx-auto">
        We don't have questions for {@schedule.name} yet. We've queued generation from your
        source material — please check back in a few minutes.
      </p>
      <div class="flex justify-center gap-3 mt-6">
        <.link
          navigate={~p"/courses/#{@course_id}"}
          class="px-6 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors"
        >
          Go to Course Page
        </.link>
        <.link
          navigate={~p"/courses/#{@course_id}/tests/#{@schedule.id}/assess"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
        >
          Try Again
        </.link>
      </div>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil
  attr :question_number, :integer, required: true
  attr :engine_state, :map, required: true
  attr :question_stats, :map, default: nil
  attr :grading, :boolean, default: false

  defp render_question(assigns) do
    assigns =
      assign(assigns,
        topic_name:
          case Enum.at(assigns.engine_state.topics, assigns.engine_state.current_topic_index) do
            nil -> "Unknown"
            t -> t.name
          end
      )

    ~H"""
    <div :if={@question} class="bg-white rounded-2xl shadow-md p-8">
      <div class="flex items-center justify-between mb-6">
        <p class="text-sm text-[#8E8E93]">
          Question {@question_number} | Topic: {@topic_name}
        </p>
      </div>

      <div class="mb-8">
        <p class="text-lg text-[#1C1C1E] font-medium leading-relaxed">{@question.content}</p>
      </div>

      <%= case @question.question_type do %>
        <% :multiple_choice -> %>
          <.render_mcq_options
            question={@question}
            selected_answer={@selected_answer}
            feedback={@feedback}
          />
        <% :true_false -> %>
          <.render_true_false
            selected_answer={@selected_answer}
            feedback={@feedback}
          />
        <% _other -> %>
          <.render_text_input
            selected_answer={@selected_answer}
            feedback={@feedback}
          />
      <% end %>

      <div :if={@feedback} class="mt-6">
        <div class={[
          "p-4 rounded-xl flex items-center gap-3",
          if(@feedback.is_correct, do: "bg-[#E8F8EB]", else: "bg-red-50")
        ]}>
          <.icon
            name={if(@feedback.is_correct, do: "hero-check-circle", else: "hero-x-circle")}
            class={[
              "w-6 h-6",
              if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
            ]}
          />
          <div>
            <p class={[
              "font-medium",
              if(@feedback.is_correct, do: "text-[#4CD964]", else: "text-[#FF3B30]")
            ]}>
              {if @feedback.is_correct, do: "Correct!", else: "Incorrect"}
            </p>
            <p
              :if={!@feedback.is_correct and is_nil(@feedback[:ai_feedback])}
              class="text-sm text-[#8E8E93] mt-1"
            >
              Correct answer: {@feedback.correct_answer}
            </p>
            <p
              :if={!@feedback.is_correct and @feedback[:ai_feedback]}
              class="text-sm text-[#8E8E93] mt-1"
            >
              {@feedback.ai_feedback}
            </p>
          </div>
        </div>

        <%!-- Community stats - shown after answering --%>
        <.render_community_stats :if={@question_stats} stats={@question_stats} />

        <div class="flex justify-end mt-4">
          <button
            phx-click="next_question"
            class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-6 py-2 rounded-full shadow-md transition-colors"
          >
            Next Question
          </button>
        </div>
      </div>

      <div :if={@feedback == nil and @grading} class="flex justify-end mt-6">
        <div class="flex items-center gap-2 text-[#8E8E93]">
          <div class="w-4 h-4 border-2 border-[#4CD964] border-t-transparent rounded-full animate-spin">
          </div>
          <span class="text-sm">Grading your answer...</span>
        </div>
      </div>

      <div :if={@feedback == nil and !@grading} class="flex justify-end mt-6">
        <button
          phx-click="submit_answer"
          disabled={@selected_answer == nil}
          class={[
            "font-medium px-6 py-2 rounded-full shadow-md transition-colors",
            if(@selected_answer,
              do: "bg-[#4CD964] hover:bg-[#3DBF55] text-white",
              else: "bg-[#E5E5EA] text-[#8E8E93] cursor-not-allowed"
            )
          ]}
        >
          Submit Answer
        </button>
      </div>
    </div>
    """
  end

  attr :question, :map, required: true
  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil

  defp render_mcq_options(assigns) do
    options = assigns.question.options || %{}

    sorted_options =
      options
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {key, value} -> %{key: key, value: value} end)

    assigns = assign(assigns, sorted_options: sorted_options)

    ~H"""
    <div class="space-y-3">
      <button
        :for={opt <- @sorted_options}
        type="button"
        phx-click="select_answer"
        phx-value-answer={opt.key}
        disabled={@feedback != nil}
        class={[
          "w-full text-left p-4 rounded-xl border-2 transition-colors",
          cond do
            @feedback != nil and opt.key == @feedback.correct_answer ->
              "border-[#4CD964] bg-[#E8F8EB]"

            @feedback != nil and opt.key == @selected_answer and not @feedback.is_correct ->
              "border-[#FF3B30] bg-red-50"

            @selected_answer == opt.key ->
              "border-[#4CD964] bg-[#E8F8EB]"

            true ->
              "border-[#E5E5EA] hover:border-[#4CD964] hover:bg-[#F5F5F7]"
          end
        ]}
      >
        <span class="font-medium text-[#1C1C1E]">{opt.key}.</span>
        <span class="ml-2 text-[#1C1C1E]">{opt.value}</span>
      </button>
    </div>
    """
  end

  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil

  defp render_true_false(assigns) do
    ~H"""
    <div class="flex gap-4">
      <button
        :for={value <- ["True", "False"]}
        type="button"
        phx-click="select_answer"
        phx-value-answer={value}
        disabled={@feedback != nil}
        class={[
          "flex-1 p-4 rounded-xl border-2 text-center font-medium transition-colors",
          cond do
            @feedback != nil and String.downcase(value) == String.downcase(@feedback.correct_answer) ->
              "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]"

            @feedback != nil and @selected_answer == value and not @feedback.is_correct ->
              "border-[#FF3B30] bg-red-50 text-[#FF3B30]"

            @selected_answer == value ->
              "border-[#4CD964] bg-[#E8F8EB] text-[#4CD964]"

            true ->
              "border-[#E5E5EA] hover:border-[#4CD964] text-[#1C1C1E]"
          end
        ]}
      >
        {value}
      </button>
    </div>
    """
  end

  attr :selected_answer, :string, default: nil
  attr :feedback, :map, default: nil

  defp render_text_input(assigns) do
    ~H"""
    <div>
      <form phx-change="update_text_answer">
        <textarea
          name="answer"
          placeholder="Type your answer..."
          disabled={@feedback != nil}
          rows="4"
          class="w-full px-4 py-3 bg-[#F5F5F7] border border-transparent focus:border-[#4CD964] rounded-xl outline-none transition-colors resize-none"
        >{@selected_answer}</textarea>
      </form>
    </div>
    """
  end

  attr :summary, :map, required: true
  attr :schedule, :map, required: true
  attr :previous_aggregate_score, :any, default: nil

  defp render_summary(assigns) do
    assigns =
      assign(assigns,
        has_needs_work: Enum.any?(assigns.summary.topic_results, &(not &1.mastered)),
        score_delta: score_delta(assigns.summary, assigns.previous_aggregate_score)
      )

    ~H"""
    <div class="bg-white rounded-2xl shadow-md p-8">
      <div class="text-center mb-8">
        <.icon name="hero-trophy" class="w-16 h-16 text-[#4CD964] mx-auto mb-4" />
        <h2 class="text-2xl font-bold text-[#1C1C1E]">Assessment Complete!</h2>
        <p class="text-[#8E8E93] mt-2">{@schedule.name}</p>
      </div>

      <div class="bg-[#F5F5F7] rounded-xl p-6 mb-6">
        <div class="text-center">
          <p class="text-4xl font-bold text-[#4CD964]">{@summary.overall_score}%</p>
          <p class="text-sm text-[#8E8E93] mt-1">
            {@summary.total_correct} of {@summary.total_questions} correct
          </p>
          <%!-- Teacher-review fix #6: readiness delta vs last retake. This
               is the progress signal that makes the "again-and-again until
               100% ready" loop feel like progress. --%>
          <div :if={@score_delta} class="mt-3 inline-flex items-center gap-1.5 text-xs font-medium">
            <span class={[
              "px-3 py-1 rounded-full",
              cond do
                @score_delta.points > 0 -> "bg-[#E8F8EB] text-[#4CD964]"
                @score_delta.points < 0 -> "bg-red-100 text-[#FF3B30]"
                true -> "bg-[#F5F5F7] text-[#8E8E93]"
              end
            ]}>
              <%= cond do %>
                <% @score_delta.points > 0 -> %>
                  ▲ +{@score_delta.points}pts since last attempt ({@score_delta.previous}% → {@summary.overall_score}%)
                <% @score_delta.points < 0 -> %>
                  ▼ {@score_delta.points}pts since last attempt ({@score_delta.previous}% → {@summary.overall_score}%)
                <% true -> %>
                  Same as last attempt ({@summary.overall_score}%)
              <% end %>
            </span>
          </div>
        </div>
      </div>

      <div :if={@summary.topic_results != []} class="space-y-3 mb-8">
        <h3 class="font-semibold text-[#1C1C1E]">Results by Topic</h3>
        <div
          :for={result <- @summary.topic_results}
          class="flex items-center justify-between p-3 bg-[#F5F5F7] rounded-xl"
        >
          <div>
            <p class="font-medium text-[#1C1C1E]">{result.topic_name}</p>
            <p class="text-xs text-[#8E8E93]">{result.correct}/{result.total} correct</p>
          </div>
          <div class="flex items-center gap-2">
            <span class={[
              "px-3 py-1 rounded-full text-xs font-medium",
              if(result.mastered,
                do: "bg-[#E8F8EB] text-[#4CD964]",
                else: "bg-red-100 text-[#FF3B30]"
              )
            ]}>
              {if result.mastered, do: "Mastered", else: "Needs Work"}
            </span>
            <span class="font-bold text-[#1C1C1E]">{result.score}%</span>
          </div>
        </div>
      </div>

      <%!-- Teacher-review fix #1: primary CTA now routes to weak-topic
           practice scoped to this schedule. "Retake" demoted to secondary
           — the mastery loop says practice weak topics FIRST, then retake. --%>
      <div class="flex flex-col items-center gap-3">
        <.link
          :if={@has_needs_work}
          navigate={~p"/courses/#{@schedule.course_id}/practice?schedule_id=#{@schedule.id}"}
          class="bg-[#4CD964] hover:bg-[#3DBF55] text-white font-medium px-8 py-3 rounded-full shadow-md transition-colors inline-flex items-center gap-2"
        >
          <.icon name="hero-academic-cap" class="w-5 h-5" /> Practice Weak Topics
        </.link>
        <div class="flex justify-center gap-3">
          <.link
            navigate={~p"/courses/#{@schedule.course_id}/tests"}
            class="px-5 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors text-sm"
          >
            Back to Tests
          </.link>
          <.link
            navigate={~p"/courses/#{@schedule.course_id}/tests/#{@schedule.id}/assess"}
            class="px-5 py-2 border border-[#E5E5EA] text-[#1C1C1E] font-medium rounded-full hover:bg-[#F5F5F7] transition-colors text-sm"
          >
            Retake Assessment
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # Compute the delta between the current summary score and the most recent
  # prior attempt. Returns nil when there is no prior (first attempt) so the
  # badge can be omitted entirely — "First attempt" would be noise.
  defp score_delta(_summary, nil), do: nil

  defp score_delta(%{overall_score: current}, previous)
       when is_number(current) and is_number(previous) do
    %{
      previous: round(previous),
      points: round(current - previous)
    }
  end

  defp score_delta(_, _), do: nil

  attr :stats, :map, required: true

  defp render_community_stats(assigns) do
    correct_pct =
      if assigns.stats.total_attempts > 0 do
        Float.round(assigns.stats.correct_attempts / assigns.stats.total_attempts * 100, 0)
      else
        0
      end

    assigns = assign(assigns, correct_pct: correct_pct)

    ~H"""
    <div class="mt-3 flex items-center gap-2 text-xs text-[#8E8E93]">
      <.icon name="hero-users" class="w-4 h-4" />
      <span>
        <span class="font-medium">{trunc(@correct_pct)}%</span>
        of students got this right
        <span class="text-[#C7C7CC]">({@stats.total_attempts} attempts)</span>
      </span>
    </div>
    """
  end
end
