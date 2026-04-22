defmodule FunSheep.Courses.TOCRebase do
  @moduledoc """
  Rebase a course's table-of-contents onto a more-complete source without
  destroying student attempt history.

  ## The problem

  A course's TOC gets discovered from whatever materials are available:
  first a web scrape (approximate), then a partial textbook OCR (better),
  then a full textbook OCR (ground truth). Whichever runs first becomes
  the course's chapter list. If the later, better discovery finds 42
  chapters where the first found 16, we need to switch to the 42 —
  WITHOUT wiping the chapters the student has already practiced against.

  ## How we decide which TOC wins

  Each discovery run gets a `DiscoveredTOC` row with a `score`:

      score = authority_weight(source) *
              ln(1 + chapter_count) *
              ln(1 + ocr_char_count)

      authority_weight = %{web: 1, textbook_partial: 3, textbook_full: 10}

  A new TOC replaces the current one only when
  `score(new) > score(current) * @improvement_gate` — a 20% gate that
  prevents thrashing on near-equal discoveries.

  ## Preserving attempts (the invariant)

  `apply/2` is a join, not a replace:

    * Every new-TOC chapter fuzzy-matches an existing chapter (normalized
      name, trigram similarity ≥ @match_threshold) → keep the existing
      chapter id, rename it to the new TOC's name.
    * Every new-TOC chapter that didn't match → create a fresh chapter.
    * Every existing chapter that didn't match AND has no question
      attempts → delete.
    * Every existing chapter that didn't match AND has attempts → keep
      as-is, mark with an "orphan in new TOC" flag in metadata.

  Net: a student's `question_attempts` rows are never invalidated by a
  rebase; their chapter_ids remain pointing at preserved chapters.

  ## Typical caller flow

      {:ok, toc} = TOCRebase.propose(course_id, "textbook_full", %{
        chapters: chapters,
        ocr_char_count: ocr_chars
      })

      case TOCRebase.compare(toc, TOCRebase.current(course_id)) do
        :new_better ->
          {:ok, _} = TOCRebase.apply(toc, course_id)
        _ ->
          :ok  # keep candidate; UI surfaces it for manual review
      end
  """

  import Ecto.Query

  alias FunSheep.Courses.{Chapter, Course, DiscoveredTOC, Section, TOCAcknowledgement}
  alias FunSheep.Questions.{Question, QuestionAttempt}
  alias FunSheep.Repo

  require Logger

  @authority_weight %{"web" => 1.0, "textbook_partial" => 3.0, "textbook_full" => 10.0}
  @improvement_gate 1.2
  @match_threshold 0.6

  # Overwhelming improvement — auto-apply without any human in the loop
  # (provided attempts are safe). Chosen so a clean web → textbook_full
  # upgrade (10× authority weight) clears it easily, but a small chapter
  # count bump on the same source doesn't.
  @auto_apply_gate 5.0

  # A user counts as "active on this course" when they've answered ≥N
  # questions in the trailing window. Active users have authority to
  # approve material pending rebases (after the creator window elapses).
  @active_attempts_threshold 5
  @active_window_days 30

  # Escalation window — active users can approve only after the creator
  # has had this many days to respond first. (The 14-day admin fallback
  # lives in the escalation worker, which is a follow-up PR.)
  @creator_window_days 7

  # Creator inactivity threshold — after this, the course becomes
  # "adoptable" by any active user.
  @inactive_creator_threshold_days 90

  ## --- Public API -------------------------------------------------------

  @doc """
  Compute the score for a TOC candidate. Pure function — takes the raw
  inputs the caller already has so we don't need a DB round-trip.
  """
  @spec score(String.t(), non_neg_integer(), non_neg_integer()) :: float()
  def score(source, chapter_count, ocr_char_count)
      when is_binary(source) and is_integer(chapter_count) and is_integer(ocr_char_count) do
    weight = Map.get(@authority_weight, source, 1.0)
    chapter_factor = :math.log(1 + max(chapter_count, 0))
    ocr_factor = :math.log(1 + max(ocr_char_count, 0))

    (weight * chapter_factor * ocr_factor)
    |> Float.round(4)
  end

  @doc """
  Record a freshly-discovered TOC as a candidate row. Returns the inserted
  `DiscoveredTOC` struct. Does not change the current live chapters.

  `chapters` is the list the discovery worker returned, shape:

      [%{"name" => "Ch 1", "sections" => ["1.1", "1.2"]}, ...]

  Accepts either string or atom keys; normalizes to string keys on the way
  in so the JSON column stays stable.
  """
  @spec propose(String.t(), String.t(), map()) ::
          {:ok, DiscoveredTOC.t()} | {:error, Ecto.Changeset.t()}
  def propose(course_id, source, %{chapters: chapters} = attrs) when is_list(chapters) do
    normalized = Enum.map(chapters, &normalize_chapter/1)
    chapter_count = length(normalized)
    ocr_chars = Map.get(attrs, :ocr_char_count, 0)

    %DiscoveredTOC{}
    |> DiscoveredTOC.changeset(%{
      course_id: course_id,
      source: source,
      chapter_count: chapter_count,
      ocr_char_count: ocr_chars,
      chapters: normalized,
      score: score(source, chapter_count, ocr_chars)
    })
    |> Repo.insert()
  end

  @doc """
  Return the currently-applied TOC for a course, or nil if none has ever
  been applied (brand-new course whose first discovery hasn't landed yet).
  """
  @spec current(String.t()) :: DiscoveredTOC.t() | nil
  def current(course_id) do
    from(t in DiscoveredTOC,
      where: t.course_id == ^course_id,
      where: not is_nil(t.applied_at),
      where: is_nil(t.superseded_at),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  History of every TOC ever recorded for this course, newest first.
  Powers the admin history drawer.
  """
  @spec list_history(String.t()) :: [DiscoveredTOC.t()]
  def list_history(course_id) do
    from(t in DiscoveredTOC,
      where: t.course_id == ^course_id,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Given a freshly proposed TOC and the course it targets, return the
  action the worker should take. This is the community-approval router:

    * `:auto_apply` — overwhelming improvement AND no risk to existing
      attempts. Safe to apply silently; notify users after.
    * `{:pending, reason}` — material improvement that requires a human:
      * `:needs_creator_approval` — creator is active; notify them.
      * `:needs_active_users_approval` — creator is inactive; any active
        user on the course can approve.
      * `:needs_admin_approval` — no creator, no active users, or
        attempts at risk — only admin can resolve.
    * `:no_change` — score didn't improve enough; keep the candidate
      row but don't do anything.

  `uploader_id` is the UserRole who triggered the discovery (uploaded
  the new textbook). The uploader's activity can unlock auto-apply on
  safe material changes they proposed themselves.
  """
  @spec decide_action(DiscoveredTOC.t(), DiscoveredTOC.t() | nil, String.t() | nil) ::
          :auto_apply
          | {:pending,
             :needs_creator_approval | :needs_active_users_approval | :needs_admin_approval}
          | :no_change
  def decide_action(%DiscoveredTOC{} = _new_toc, nil, _uploader_id), do: :auto_apply

  def decide_action(%DiscoveredTOC{} = new_toc, %DiscoveredTOC{} = current_toc, uploader_id) do
    course = Repo.get!(Course, current_toc.course_id)
    ratio = new_toc.score / max(current_toc.score, 0.001)
    safe? = attempts_safe?(new_toc, current_toc.course_id)

    cond do
      ratio <= @improvement_gate ->
        :no_change

      safe? and ratio >= @auto_apply_gate ->
        :auto_apply

      safe? and uploader_active_on?(uploader_id, current_toc.course_id) ->
        # Uploader has skin in the game (≥5 attempts) AND their upload
        # doesn't risk anyone's existing progress — let it through.
        :auto_apply

      not safe? ->
        # Would orphan chapters that students OTHER than the uploader
        # have answered on. Admin fallback.
        {:pending, :needs_admin_approval}

      creator_active?(course) ->
        {:pending, :needs_creator_approval}

      active_users_exist?(course.id) ->
        {:pending, :needs_active_users_approval}

      true ->
        {:pending, :needs_admin_approval}
    end
  end

  @doc """
  Store a proposed TOC as pending on the course record. Called by the
  worker when `decide_action/3` returns `{:pending, _reason}`.
  """
  @spec mark_pending(Course.t(), DiscoveredTOC.t(), String.t() | nil) ::
          {:ok, Course.t()} | {:error, Ecto.Changeset.t()}
  def mark_pending(%Course{} = course, %DiscoveredTOC{} = toc, uploader_id) do
    course
    |> Course.changeset(%{
      pending_toc_id: toc.id,
      pending_toc_proposed_by_id: uploader_id,
      pending_toc_proposed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Clear a pending proposal (e.g., after it's been applied or rejected).
  """
  @spec clear_pending(Course.t()) :: {:ok, Course.t()} | {:error, Ecto.Changeset.t()}
  def clear_pending(%Course{} = course) do
    course
    |> Course.changeset(%{
      pending_toc_id: nil,
      pending_toc_proposed_by_id: nil,
      pending_toc_proposed_at: nil
    })
    |> Repo.update()
  end

  @doc """
  Can this user approve a specific pending TOC on this course right now?
  Encodes the tier escalation:

    * Admin → always.
    * Creator + still active → immediately.
    * Uploader (proposed this TOC) + active + rebase is attempts-safe →
      immediately (skin in the game, bounded risk).
    * Any active user → only after the creator window elapses
      (`@creator_window_days` since proposal).
    * Admin fallback — after `@active_majority_window_days`, only admin
      can resolve (handled by the escalation worker flipping the
      `:needs_admin_approval` reason).
  """
  @spec can_approve?(map() | nil, Course.t(), DiscoveredTOC.t() | nil) :: boolean()
  def can_approve?(nil, _course, _toc), do: false

  def can_approve?(%{"role" => "admin"}, _course, _toc), do: true
  def can_approve?(%{role: "admin"}, _course, _toc), do: true
  def can_approve?(_user, _course, nil), do: false

  def can_approve?(user, %Course{} = course, %DiscoveredTOC{} = toc) do
    user_role_id = user["user_role_id"] || user[:user_role_id] || user["id"]

    cond do
      is_nil(user_role_id) ->
        false

      # Creator still active → top authority.
      user_role_id == course.created_by_id and user_activity_count(user_role_id, course.id) > 0 ->
        true

      # Uploader, active, and the rebase is attempts-safe.
      user_role_id == course.pending_toc_proposed_by_id and
        active_on?(user_role_id, course.id) and
          attempts_safe?(toc, course.id) ->
        true

      # Active user — only after the creator window has elapsed.
      active_on?(user_role_id, course.id) and
          proposal_age_days(course) >= @creator_window_days ->
        true

      true ->
        false
    end
  end

  @doc """
  Apply a pending TOC (authorization should be checked by the caller
  via `can_approve?/3`). Wraps `apply/2` and clears the pending state.
  """
  @spec approve!(Course.t(), DiscoveredTOC.t()) :: {:ok, map()} | {:error, term()}
  def approve!(%Course{} = course, %DiscoveredTOC{} = toc) do
    # `apply/2` would collide with Kernel.apply/2 — fully qualify.
    with {:ok, stats} <- __MODULE__.apply(toc, course.id),
         {:ok, _} <- clear_pending(Repo.get!(Course, course.id)) do
      {:ok, stats}
    end
  end

  @doc """
  Reject a pending proposal — drops the pending_toc_* pointers without
  applying the TOC. The DiscoveredTOC row stays for audit. Authorization
  is the caller's responsibility.
  """
  @spec reject!(Course.t()) :: {:ok, Course.t()} | {:error, Ecto.Changeset.t()}
  def reject!(%Course{} = course), do: clear_pending(course)

  ## --- Activity + authority helpers ------------------------------------

  @doc """
  Is this user-role active on the given course? Active means at least
  `@active_attempts_threshold` recorded answers within the trailing
  `@active_window_days`.
  """
  @spec active_on?(String.t() | nil, String.t()) :: boolean()
  def active_on?(nil, _course_id), do: false

  def active_on?(user_role_id, course_id) do
    user_activity_count(user_role_id, course_id) >= @active_attempts_threshold
  end

  @doc false
  def user_activity_count(user_role_id, course_id) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@active_window_days * 24 * 60 * 60, :second)

    from(a in QuestionAttempt,
      join: q in Question,
      on: q.id == a.question_id,
      where:
        a.user_role_id == ^user_role_id and
          q.course_id == ^course_id and
          a.inserted_at >= ^since,
      select: count(a.id)
    )
    |> Repo.one()
  end

  @doc """
  Return the UserRole IDs that are currently active on the course.
  """
  @spec active_users_for(String.t()) :: [String.t()]
  def active_users_for(course_id) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@active_window_days * 24 * 60 * 60, :second)

    from(a in QuestionAttempt,
      join: q in Question,
      on: q.id == a.question_id,
      where: q.course_id == ^course_id and a.inserted_at >= ^since,
      group_by: a.user_role_id,
      having: count(a.id) >= ^@active_attempts_threshold,
      select: a.user_role_id
    )
    |> Repo.all()
  end

  @doc """
  Is the creator currently active on this course? Returns false if the
  course has no creator at all.
  """
  @spec creator_active?(Course.t()) :: boolean()
  def creator_active?(%Course{created_by_id: nil}), do: false
  def creator_active?(%Course{created_by_id: id, id: cid}), do: active_on?(id, cid)

  @doc """
  Can this user adopt the course? True when the creator has been
  inactive for ≥ #{@inactive_creator_threshold_days} days AND this user
  is currently active on the course.
  """
  @spec adoptable_by?(String.t(), Course.t()) :: boolean()
  def adoptable_by?(user_role_id, %Course{} = course) do
    cond do
      is_nil(user_role_id) ->
        false

      user_role_id == course.created_by_id ->
        # Already the creator — nothing to adopt.
        false

      not active_on?(user_role_id, course.id) ->
        false

      is_nil(course.created_by_id) ->
        # No creator at all — anyone active can claim.
        true

      creator_inactive_for_days?(course, @inactive_creator_threshold_days) ->
        true

      true ->
        false
    end
  end

  @doc """
  Promote a user to creator. Authorization is the caller's responsibility
  (usually `adoptable_by?/2`).
  """
  @spec adopt!(Course.t(), String.t()) :: {:ok, Course.t()} | {:error, Ecto.Changeset.t()}
  def adopt!(%Course{} = course, new_creator_id) do
    course
    |> Course.changeset(%{created_by_id: new_creator_id})
    |> Repo.update()
  end

  ## --- Acknowledgement (post-rebase banner dismiss) --------------------

  @doc """
  Record that this user has dismissed the "course updated" banner for
  a specific applied TOC. Idempotent — upserts on (user_role_id,
  discovered_toc_id).
  """
  @spec acknowledge!(String.t(), String.t(), String.t()) ::
          {:ok, TOCAcknowledgement.t()} | {:error, Ecto.Changeset.t()}
  def acknowledge!(user_role_id, course_id, discovered_toc_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %TOCAcknowledgement{}
    |> TOCAcknowledgement.changeset(%{
      user_role_id: user_role_id,
      course_id: course_id,
      discovered_toc_id: discovered_toc_id,
      dismissed_at: now
    })
    |> Repo.insert(
      on_conflict: {:replace, [:dismissed_at, :updated_at]},
      conflict_target: [:user_role_id, :discovered_toc_id]
    )
  end

  @doc """
  Has this user NOT yet acknowledged the currently-applied TOC for this
  course? Returns true iff the banner should still be shown.
  """
  @spec needs_acknowledgement?(String.t() | nil, Course.t()) :: boolean()
  def needs_acknowledgement?(nil, _course), do: false

  def needs_acknowledgement?(user_role_id, %Course{id: course_id}) do
    case current(course_id) do
      nil ->
        false

      %DiscoveredTOC{id: toc_id} ->
        ack_exists? =
          from(a in TOCAcknowledgement,
            where: a.user_role_id == ^user_role_id and a.discovered_toc_id == ^toc_id,
            select: 1,
            limit: 1
          )
          |> Repo.one()

        is_nil(ack_exists?)
    end
  end

  ## --- Compare (back-compat for earlier callers) -----------------------

  @doc """
  Decide how two TOCs compare:

    * `:no_current` — no applied TOC yet; `new` should be applied on first run.
    * `:new_better` — new beats current by the improvement gate AND attempt safety holds.
    * `:insufficient_gain` — new is better but not enough to justify churn.
    * `:attempt_risk` — new scores higher but would orphan chapters with attempts.
    * `:current_better_or_equal` — new is not actually better.
  """
  @spec compare(DiscoveredTOC.t(), DiscoveredTOC.t() | nil) ::
          :no_current
          | :new_better
          | :insufficient_gain
          | :attempt_risk
          | :current_better_or_equal
  def compare(%DiscoveredTOC{} = _new, nil), do: :no_current

  def compare(%DiscoveredTOC{} = new, %DiscoveredTOC{} = current) do
    cond do
      new.score <= current.score ->
        :current_better_or_equal

      new.score <= current.score * @improvement_gate ->
        :insufficient_gain

      not attempts_safe?(new, current.course_id) ->
        :attempt_risk

      true ->
        :new_better
    end
  end

  @doc """
  Apply `new_toc` as the course's current TOC. Non-destructively rebases:
  matched chapters keep their ids, unmatched-with-attempts chapters are
  preserved as orphans, unmatched-empty chapters are deleted, genuinely
  new chapters are created.

  Returns `{:ok, %{kept: N, renamed: N, created: N, orphaned: N, deleted: N}}`
  or `{:error, reason}` if the transaction failed.
  """
  @spec apply(DiscoveredTOC.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def apply(%DiscoveredTOC{} = new_toc, course_id) do
    Repo.transaction(fn ->
      current_chapters = load_current_chapters(course_id)
      chapters_with_attempts = chapter_ids_with_attempts(course_id)

      plan = plan_rebase(new_toc.chapters, current_chapters, chapters_with_attempts)
      created_ids = execute_plan(plan, course_id)

      mark_applied(new_toc, course_id)

      %{
        kept: length(plan.matched),
        created: length(plan.created),
        orphaned: length(plan.orphans),
        deleted: length(plan.deletes),
        # Chapter ids that were inserted fresh during this rebase. Callers
        # use this to proactively enqueue question generation for just the
        # new chapters (e.g., after a 16→42 chapter expansion, we don't
        # want to regenerate questions for the 16 preserved chapters).
        new_chapter_ids: created_ids
      }
    end)
  end

  ## --- Internals --------------------------------------------------------

  # Every question with at least one attempt "locks" its chapter — we
  # can't delete that chapter during rebase. Returns a MapSet of
  # chapter_ids for fast membership checks.
  defp chapter_ids_with_attempts(course_id) do
    from(q in Question,
      join: a in QuestionAttempt,
      on: a.question_id == q.id,
      where: q.course_id == ^course_id and not is_nil(q.chapter_id),
      distinct: true,
      select: q.chapter_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_current_chapters(course_id) do
    from(ch in Chapter,
      where: ch.course_id == ^course_id,
      order_by: ch.position,
      preload: [:sections]
    )
    |> Repo.all()
  end

  # Build the full rebase plan WITHOUT touching the DB. Made pure so we
  # can unit-test the matching + attempt-safety math directly.
  @doc false
  def plan_rebase(new_chapters, current_chapters, chapters_with_attempts) do
    {matched, unmatched_new} =
      Enum.reduce(new_chapters, {[], []}, fn new_ch, {matched_acc, unmatched_acc} ->
        new_name = Map.get(new_ch, "name", "")

        case best_match(new_name, current_chapters, matched_acc) do
          nil ->
            {matched_acc, [new_ch | unmatched_acc]}

          current ->
            {[{current.id, current.name, new_ch} | matched_acc], unmatched_acc}
        end
      end)

    matched_ids = MapSet.new(matched, fn {id, _, _} -> id end)

    {orphans, deletes} =
      current_chapters
      |> Enum.reject(&MapSet.member?(matched_ids, &1.id))
      |> Enum.split_with(fn ch -> MapSet.member?(chapters_with_attempts, ch.id) end)

    %{
      matched: Enum.reverse(matched),
      created: Enum.reverse(unmatched_new),
      orphans: orphans,
      deletes: deletes
    }
  end

  defp execute_plan(
         %{matched: matched, created: created, orphans: orphans, deletes: deletes},
         course_id
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # 1. Renames (match old chapter to new TOC name + sync sections).
    Enum.with_index(matched, 1)
    |> Enum.each(fn {{chapter_id, _old_name, new_ch}, position} ->
      chapter = Repo.get!(Chapter, chapter_id)

      {:ok, _} =
        chapter
        |> Chapter.changeset(%{
          name: Map.get(new_ch, "name") || chapter.name,
          position: position
        })
        |> Repo.update()

      sync_sections(chapter_id, Map.get(new_ch, "sections") || [])
    end)

    # 2. Create brand-new chapters for unmatched new-TOC entries.
    # Collect the inserted ids so the caller can proactively enqueue
    # question generation for just these (not the preserved ones).
    next_position = length(matched) + 1

    created_ids =
      created
      |> Enum.with_index(next_position)
      |> Enum.map(fn {new_ch, position} ->
        {:ok, chapter} =
          %Chapter{}
          |> Chapter.changeset(%{
            name: Map.get(new_ch, "name") || "Unnamed Chapter",
            position: position,
            course_id: course_id
          })
          |> Repo.insert()

        sync_sections(chapter.id, Map.get(new_ch, "sections") || [])
        chapter.id
      end)

    # 3. Mark orphans (current chapters with attempts but no match in the
    # new TOC). They stay in the DB; `orphaned_at` surfaces them in the
    # admin UI.
    orphan_position = length(matched) + length(created) + 1

    orphans
    |> Enum.with_index(orphan_position)
    |> Enum.each(fn {chapter, position} ->
      chapter
      |> Chapter.changeset(%{position: position, orphaned_at: now})
      |> Repo.update()
    end)

    # 4. Delete empty orphans (no attempts — safe to drop).
    Enum.each(deletes, fn chapter -> Repo.delete!(chapter) end)

    created_ids
  end

  # For each new-TOC section name: match to an existing section (by
  # fuzzy name), preserving its id; else create. Never delete a section
  # here — sections with attempts must survive too, and tracking
  # per-section attempt locks isn't worth it for v1.
  defp sync_sections(chapter_id, new_section_names) do
    existing =
      from(s in Section, where: s.chapter_id == ^chapter_id, order_by: s.position)
      |> Repo.all()

    {matched, unmatched} =
      Enum.reduce(new_section_names, {[], []}, fn name, {m, u} ->
        case best_section_match(name, existing, m) do
          nil -> {m, [name | u]}
          section -> {[{section.id, name} | m], u}
        end
      end)

    # Rename matches
    matched_ids = MapSet.new(matched, fn {id, _} -> id end)

    Enum.with_index(matched, 1)
    |> Enum.each(fn {{section_id, new_name}, position} ->
      section = Repo.get!(Section, section_id)

      section
      |> Section.changeset(%{name: new_name, position: position})
      |> Repo.update!()
    end)

    # Bump position on untouched existing sections so new ones can slot in after.
    next_pos = length(matched) + 1

    # Create unmatched as new sections after renamed ones.
    unmatched
    |> Enum.reverse()
    |> Enum.with_index(next_pos)
    |> Enum.each(fn {name, position} ->
      %Section{}
      |> Section.changeset(%{
        name: name,
        position: position,
        chapter_id: chapter_id
      })
      |> Repo.insert!()
    end)

    # Existing sections not matched: leave them where they are but bump
    # their position past the new ones so UI ordering reflects the new
    # TOC. Never delete — attempts might reference them.
    tail_start = next_pos + length(unmatched)

    existing
    |> Enum.reject(&MapSet.member?(matched_ids, &1.id))
    |> Enum.with_index(tail_start)
    |> Enum.each(fn {section, position} ->
      section
      |> Section.changeset(%{position: position})
      |> Repo.update!()
    end)
  end

  # Returns the best-matching current chapter for `new_name` that hasn't
  # already been claimed by another new-TOC entry, or nil if no match
  # clears @match_threshold.
  defp best_match(new_name, current_chapters, already_matched) do
    claimed = MapSet.new(already_matched, fn {id, _, _} -> id end)

    current_chapters
    |> Enum.reject(&MapSet.member?(claimed, &1.id))
    |> Enum.map(fn ch -> {ch, similarity(new_name, ch.name)} end)
    |> Enum.filter(fn {_ch, sim} -> sim >= @match_threshold end)
    |> Enum.max_by(fn {_ch, sim} -> sim end, fn -> nil end)
    |> case do
      nil -> nil
      {ch, _sim} -> ch
    end
  end

  defp best_section_match(new_name, existing_sections, already_matched) do
    claimed = MapSet.new(already_matched, fn {id, _} -> id end)

    existing_sections
    |> Enum.reject(&MapSet.member?(claimed, &1.id))
    |> Enum.map(fn s -> {s, similarity(new_name, s.name)} end)
    |> Enum.filter(fn {_s, sim} -> sim >= @match_threshold end)
    |> Enum.max_by(fn {_s, sim} -> sim end, fn -> nil end)
    |> case do
      nil -> nil
      {s, _sim} -> s
    end
  end

  # Jaccard similarity on normalized token sets. Cheap, reliable,
  # no pg_trgm dependency. Good enough for "Chapter 1 Cells" vs
  # "Chapter 1: The Cell" (identical token overlap → 1.0) or
  # "Photosynthesis" vs "Photo synthesis" (close).
  @doc false
  def similarity(a, b) when is_binary(a) and is_binary(b) do
    tokens_a = tokens(a)
    tokens_b = tokens(b)

    cond do
      tokens_a == MapSet.new() and tokens_b == MapSet.new() ->
        1.0

      tokens_a == MapSet.new() or tokens_b == MapSet.new() ->
        0.0

      true ->
        inter = MapSet.intersection(tokens_a, tokens_b) |> MapSet.size()
        union = MapSet.union(tokens_a, tokens_b) |> MapSet.size()
        inter / union
    end
  end

  def similarity(_, _), do: 0.0

  defp tokens(s) do
    s
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in ~w(the a an of and or to in on at for with)))
    |> Enum.map(&stem/1)
    |> MapSet.new()
  end

  # Drop trailing 's'/'es' on tokens ≥ 4 chars so "cells" and "cell" compare
  # equal. Not a full Porter stemmer — just enough to stop chapter-name
  # plurality from blocking a match.
  defp stem(token) when byte_size(token) >= 5 do
    cond do
      String.ends_with?(token, "ies") -> String.slice(token, 0..-4//1) <> "y"
      String.ends_with?(token, "es") -> String.slice(token, 0..-3//1)
      String.ends_with?(token, "s") -> String.slice(token, 0..-2//1)
      true -> token
    end
  end

  defp stem(token) when byte_size(token) >= 4 do
    if String.ends_with?(token, "s"), do: String.slice(token, 0..-2//1), else: token
  end

  defp stem(token), do: token

  # A proposed TOC is "attempts-safe" when every existing chapter that
  # has student attempts can be accounted for — either it fuzzy-matches
  # something in the new TOC, OR it's going to be preserved as an orphan.
  # Since the orphan path is always available, this is really a heuristic
  # for "is this rebase worth showing as auto-apply?" — if too many
  # active chapters get orphaned, prefer to surface the rebase for
  # manual review instead.
  defp attempts_safe?(new_toc, course_id) do
    current_chapters = load_current_chapters(course_id)
    active = chapter_ids_with_attempts(course_id)

    active_chapters = Enum.filter(current_chapters, &MapSet.member?(active, &1.id))

    if active_chapters == [] do
      true
    else
      matched_count =
        Enum.count(active_chapters, fn ch ->
          Enum.any?(new_toc.chapters, fn new_ch ->
            similarity(Map.get(new_ch, "name", ""), ch.name) >= @match_threshold
          end)
        end)

      # Require that most active chapters (≥80%) re-appear in the new TOC.
      matched_count / length(active_chapters) >= 0.8
    end
  end

  defp mark_applied(%DiscoveredTOC{id: id, course_id: course_id}, _course_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Supersede the currently-applied TOC (if any) in one UPDATE.
    from(t in DiscoveredTOC,
      where:
        t.course_id == ^course_id and
          not is_nil(t.applied_at) and
          is_nil(t.superseded_at) and
          t.id != ^id
    )
    |> Repo.update_all(set: [superseded_at: now, updated_at: now])

    # Mark the new one applied.
    {1, _} =
      from(t in DiscoveredTOC, where: t.id == ^id)
      |> Repo.update_all(set: [applied_at: now, superseded_at: nil, updated_at: now])

    :ok
  end

  defp normalize_chapter(%{} = ch) do
    %{
      "name" => Map.get(ch, "name") || Map.get(ch, :name) || "Unnamed Chapter",
      "sections" =>
        (Map.get(ch, "sections") || Map.get(ch, :sections) || [])
        |> Enum.map(&to_string/1)
    }
  end

  defp normalize_chapter(_), do: %{"name" => "Unnamed Chapter", "sections" => []}

  ## --- Community-approval private helpers ------------------------------

  # Is the uploader active on this course? Used to unlock auto-apply on
  # their own safe proposal.
  defp uploader_active_on?(nil, _course_id), do: false
  defp uploader_active_on?(uploader_id, course_id), do: active_on?(uploader_id, course_id)

  defp active_users_exist?(course_id), do: active_users_for(course_id) != []

  defp creator_inactive_for_days?(%Course{created_by_id: nil}, _days), do: true

  defp creator_inactive_for_days?(%Course{created_by_id: id, id: cid}, days) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-days * 24 * 60 * 60, :second)

    # Inactive iff no attempts by creator on this course within the window.
    count =
      from(a in QuestionAttempt,
        join: q in Question,
        on: q.id == a.question_id,
        where: a.user_role_id == ^id and q.course_id == ^cid and a.inserted_at >= ^since,
        select: count(a.id)
      )
      |> Repo.one()

    count == 0
  end

  defp proposal_age_days(%Course{pending_toc_proposed_at: nil}), do: 0

  defp proposal_age_days(%Course{pending_toc_proposed_at: at}) do
    DateTime.diff(DateTime.utc_now(), at, :second)
    |> div(24 * 60 * 60)
  end
end
