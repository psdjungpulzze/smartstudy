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

  alias FunSheep.Courses.{Chapter, DiscoveredTOC, Section}
  alias FunSheep.Questions.{Question, QuestionAttempt}
  alias FunSheep.Repo

  require Logger

  @authority_weight %{"web" => 1.0, "textbook_partial" => 3.0, "textbook_full" => 10.0}
  @improvement_gate 1.2
  @match_threshold 0.6

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
      execute_plan(plan, course_id)

      mark_applied(new_toc, course_id)

      %{
        kept: length(plan.matched),
        created: length(plan.created),
        orphaned: length(plan.orphans),
        deleted: length(plan.deletes)
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
    next_position = length(matched) + 1

    created
    |> Enum.with_index(next_position)
    |> Enum.each(fn {new_ch, position} ->
      {:ok, chapter} =
        %Chapter{}
        |> Chapter.changeset(%{
          name: Map.get(new_ch, "name") || "Unnamed Chapter",
          position: position,
          course_id: course_id
        })
        |> Repo.insert()

      sync_sections(chapter.id, Map.get(new_ch, "sections") || [])
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

    :ok
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
end
