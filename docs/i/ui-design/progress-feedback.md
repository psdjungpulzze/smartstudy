# Progress Feedback Patterns

Detailed guidance for implementing real-time, contextual, informative progress UI in FunSheep. This document accompanies the rule at `.claude/rules/i/progress-feedback.md`.

**Governing principle**: When a user triggers work that takes longer than ~2 seconds, they must always know *what* is happening, *where in the process* we are, and *when it will end*.

---

## 1. When This Applies

Apply this pattern to any operation where the user triggers server work that cannot complete within a single sync HTTP response. In FunSheep, that includes (non-exhaustive):

- Course generation (OCR + chapter detection + question generation)
- Question regeneration for a chapter or test
- Study path / lesson generation
- AI tutor multi-turn reasoning when visible to the user
- Bulk imports or admin batch operations
- Any Oban-backed job whose result the user is waiting on a page for

If the user is staring at the screen expecting an outcome, this rule applies.

---

## 2. Data Model for Progress Broadcasts

Standardize the shape of every progress broadcast so the frontend can render consistently without per-feature branching.

```elixir
%FunSheep.Progress.Event{
  job_id: String.t(),              # stable UUID for the whole operation
  scope: atom(),                   # :course_generation | :question_regeneration | ...
  phase: atom(),                   # :ocr | :chapter_detection | :question_gen | :finalizing
  phase_label: String.t(),         # user-facing phase name
  phase_index: pos_integer(),      # 1-based
  phase_total: pos_integer(),
  detail: String.t() | nil,        # current item name, e.g. "Chapter 3: Cell Division"
  progress: %{
    current: non_neg_integer(),
    total: non_neg_integer() | nil,  # nil only when genuinely unknown
    unit: String.t()                 # "questions", "chapters", "pages"
  },
  status: :queued | :running | :succeeded | :failed | :partial,
  error: %{code: atom(), message: String.t()} | nil,
  started_at: DateTime.t(),
  updated_at: DateTime.t()
}
```

**Rules:**
- Every broadcast must include `phase`, `phase_index`, `phase_total`, `status`.
- `detail` is required whenever there is a concrete current item (chapter, question batch, page).
- If `progress.total` is genuinely unknown, make the UI show phase-of-total progress instead — never show an unbounded spinner.
- Terminal events MUST have `status: :succeeded | :failed | :partial` and should be the last broadcast for the `job_id`.

---

## 3. Broadcasting (Phoenix PubSub)

```elixir
defmodule FunSheep.Progress do
  alias Phoenix.PubSub

  def topic(job_id), do: "progress:#{job_id}"

  def broadcast(%FunSheep.Progress.Event{job_id: id} = event) do
    PubSub.broadcast(FunSheep.PubSub, topic(id), {:progress, event})
  end

  def phase(job_id, scope, phase, phase_label, phase_index, phase_total, detail \\ nil) do
    broadcast(%FunSheep.Progress.Event{
      job_id: job_id,
      scope: scope,
      phase: phase,
      phase_label: phase_label,
      phase_index: phase_index,
      phase_total: phase_total,
      detail: detail,
      progress: %{current: 0, total: nil, unit: ""},
      status: :running,
      started_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    })
  end

  def tick(job_id, current, total, unit, detail \\ nil) do
    # Updates the counter inside the current phase
    # ...fetch current phase from ETS or pass through
  end
end
```

**Rule of thumb**: broadcast on every phase transition, every item completion, every retry, and every terminal state. Do not throttle below ~500ms for human-visible work.

---

## 4. Oban Worker Pattern

```elixir
defmodule FunSheep.Workers.GenerateQuestionsWorker do
  use Oban.Worker, queue: :ai

  alias FunSheep.Progress

  @impl true
  def perform(%Oban.Job{args: %{"job_id" => job_id, "chapter_id" => chapter_id}}) do
    chapter = Courses.get_chapter!(chapter_id)

    Progress.phase(job_id, :question_regeneration, :preparing,
      "Preparing chapter context", 1, 3, chapter.title)

    context = build_context(chapter)

    Progress.phase(job_id, :question_regeneration, :generating,
      "Generating questions", 2, 3, chapter.title)

    questions =
      1..20
      |> Enum.map(fn i ->
        q = generate_question(context, i)
        Progress.tick(job_id, i, 20, "questions", chapter.title)
        q
      end)

    Progress.phase(job_id, :question_regeneration, :saving,
      "Saving questions", 3, 3, chapter.title)

    {:ok, _} = Courses.insert_questions(chapter, questions)

    Progress.broadcast(%Progress.Event{
      job_id: job_id,
      scope: :question_regeneration,
      phase: :done,
      phase_label: "Complete",
      phase_index: 3,
      phase_total: 3,
      detail: chapter.title,
      progress: %{current: 20, total: 20, unit: "questions"},
      status: :succeeded,
      started_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    })

    :ok
  rescue
    e ->
      Progress.broadcast(%Progress.Event{
        job_id: job_id,
        scope: :question_regeneration,
        phase: :failed,
        phase_label: "Failed",
        phase_index: 0,
        phase_total: 3,
        detail: Exception.message(e),
        progress: %{current: 0, total: 0, unit: ""},
        status: :failed,
        error: %{code: :generation_error, message: Exception.message(e)},
        started_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      })
      reraise e, __STACKTRACE__
  end
end
```

---

## 5. LiveView Consumer Pattern

```elixir
defmodule FunSheepWeb.TestLive.Show do
  use FunSheepWeb, :live_view

  alias FunSheep.Progress

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    test = Courses.get_test!(id)
    {:ok, assign(socket, test: test, progress: nil)}
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    job_id = Ecto.UUID.generate()

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(FunSheep.PubSub, Progress.topic(job_id))

    %{job_id: job_id, test_id: socket.assigns.test.id}
    |> FunSheep.Workers.GenerateQuestionsWorker.new()
    |> Oban.insert()

    {:noreply, assign(socket, progress: %{status: :queued, job_id: job_id})}
  end

  @impl true
  def handle_info({:progress, %Progress.Event{} = event}, socket) do
    {:noreply, assign(socket, progress: event)}
  end
end
```

---

## 6. Progress Component (HEEX)

```heex
<div :if={@progress} class="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
  <div class="flex items-center justify-between mb-2">
    <h3 class="text-sm font-semibold text-gray-900">
      <%= @progress.phase_label %>
      <span class="text-gray-500 font-normal">
        (Step <%= @progress.phase_index %> of <%= @progress.phase_total %>)
      </span>
    </h3>
    <span :if={@progress.status == :running} class="text-xs text-gray-500">
      <%= eta_label(@progress) %>
    </span>
  </div>

  <p :if={@progress.detail} class="text-sm text-gray-700 mb-3">
    <%= @progress.detail %>
  </p>

  <div :if={@progress.progress.total && @progress.progress.total > 0} class="mb-2">
    <div class="flex justify-between text-xs text-gray-600 mb-1">
      <span>
        <%= @progress.progress.current %> of <%= @progress.progress.total %>
        <%= @progress.progress.unit %>
      </span>
      <span><%= percent(@progress.progress) %>%</span>
    </div>
    <div class="w-full bg-gray-100 rounded-full h-2">
      <div
        class="bg-[#4CD964] h-2 rounded-full transition-all duration-300"
        style={"width: #{percent(@progress.progress)}%"}
      />
    </div>
  </div>

  <div :if={@progress.status == :succeeded} class="text-sm text-green-700 font-medium">
    ✓ <%= @progress.detail || "Complete" %>
  </div>

  <div :if={@progress.status == :failed} class="text-sm text-red-600 font-medium">
    ✗ <%= @progress.error && @progress.error.message || "Something went wrong" %>
    <button phx-click="retry" class="ml-2 underline">Retry</button>
  </div>
</div>
```

---

## 7. FunSheep-Specific Applications

### Question Regeneration (the trigger for this rule)

Minimum required UI during regeneration:
- "Regenerating questions for *Chapter 3: Cell Division*" (named chapter, not "your chapter")
- "Step 2 of 3 — Generating questions" OR "12 of 20 questions generated"
- Terminal confirmation: "✓ 20 questions ready" — not silent dismissal

If multiple chapters are regenerating, show per-chapter rows, each with its own phase state. Never collapse to a single shared spinner.

### Course Generation (OCR → chapters → questions)

Phases to expose:
1. Uploading file (bytes transferred)
2. OCR extraction (`page X of N`)
3. Chapter detection ("Found 14 chapters")
4. Per-chapter question generation (`chapter N of total`, then `Q/20` within chapter)
5. Finalizing course

Surface intermediate results: once OCR finishes, the detected chapter list should appear even while question generation continues — the user wants to see value accruing.

### Study Path / Lesson Generation

- Broadcast per-lesson progress. Do not batch-complete silently.
- If generation for a topic fails, that topic shows failed; others continue. No global failure for a per-item problem.

---

## 8. Testing Progress UI

Every long-running flow needs an integration test that:

1. Starts the operation.
2. Asserts that progress events are broadcast in the expected phase order.
3. Asserts the LiveView re-renders with the correct phase label, detail, and counts.
4. Asserts the terminal state renders (success AND failure paths).

Playwright visual verification (per `.claude/rules/i/visual-testing.md`) must capture *at least one mid-progress state*, not only start and end.

---

## 9. Checklist Before Merging

- [ ] Broadcast shape matches `FunSheep.Progress.Event`
- [ ] All phases are named and indexed (`phase_index`/`phase_total`)
- [ ] Current item name (`detail`) is user-facing and domain-specific
- [ ] Progress counts come from real server work, not a timer
- [ ] User can always answer "how much longer?"
- [ ] Success and failure render as distinct terminal states
- [ ] Retry / cancel / next-action affordances exist where safe
- [ ] PubSub subscription is set up in `mount` only when `connected?/1`
- [ ] Visual test captures mid-progress state

---

## Related

- Rule: `.claude/rules/i/progress-feedback.md`
- Rule: `.claude/rules/i/ui-design.md`
- Rule: `.claude/rules/i/visual-testing.md`
