defmodule FunSheep.Courses.TOCRebaseTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Courses
  alias FunSheep.Courses.{DiscoveredTOC, TOCRebase}
  alias FunSheep.Questions

  defp create_course(attrs \\ %{}) do
    {:ok, course} =
      Courses.create_course(Map.merge(%{name: "Biology", subject: "Biology", grade: "10"}, attrs))

    course
  end

  defp create_chapter(course, name, position \\ 1) do
    {:ok, ch} =
      Courses.create_chapter(%{name: name, position: position, course_id: course.id})

    ch
  end

  defp create_user_role do
    FunSheep.ContentFixtures.create_user_role()
  end

  defp create_question_with_attempt(course, chapter, user_role) do
    {:ok, q} =
      Questions.create_question(%{
        content: "q in #{chapter.name}",
        answer: "A",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: chapter.id,
        validation_status: :passed
      })

    Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q.id,
      answer_given: "A",
      is_correct: true
    })

    q
  end

  describe "score/3" do
    test "authority_weight multiplies: textbook_full >> web for the same counts" do
      web = TOCRebase.score("web", 16, 10_000)
      full = TOCRebase.score("textbook_full", 16, 10_000)

      assert full > web * 9.9
      assert full < web * 10.1
    end

    test "monotonic in chapter_count when other inputs are equal" do
      a = TOCRebase.score("textbook_full", 16, 10_000)
      b = TOCRebase.score("textbook_full", 42, 10_000)
      assert b > a
    end

    test "monotonic in ocr_char_count when other inputs are equal" do
      a = TOCRebase.score("textbook_full", 16, 10_000)
      b = TOCRebase.score("textbook_full", 16, 200_000)
      assert b > a
    end

    test "zero inputs → score 0 (log(1) == 0)" do
      assert TOCRebase.score("textbook_full", 0, 10_000) == 0.0
      assert TOCRebase.score("textbook_full", 42, 0) == 0.0
    end

    test "unknown source defaults to weight 1.0 (web-equivalent)" do
      unknown = TOCRebase.score("vibes", 20, 5000)
      web = TOCRebase.score("web", 20, 5000)
      assert_in_delta unknown, web, 0.0001
    end
  end

  describe "similarity/2" do
    test "identical strings → 1.0" do
      assert TOCRebase.similarity("Photosynthesis", "Photosynthesis") == 1.0
    end

    test "case-insensitive and punctuation-insensitive" do
      assert TOCRebase.similarity("Chapter 1: Cells", "chapter 1 cells") == 1.0
    end

    test "fully disjoint → 0.0" do
      assert TOCRebase.similarity("Photosynthesis", "Mitochondria") == 0.0
    end

    test "partial overlap is between 0 and 1" do
      sim = TOCRebase.similarity("The Science of Biology", "Biology Science Intro")
      assert sim > 0.2
      assert sim < 1.0
    end

    test "stopwords (the, a, of) don't dominate similarity" do
      # "the" is stripped so these should still feel very similar.
      sim = TOCRebase.similarity("The Chemistry of Life", "Chemistry of Life")
      assert sim == 1.0
    end

    test "handles nil / non-binary input defensively" do
      assert TOCRebase.similarity(nil, "x") == 0.0
      assert TOCRebase.similarity("x", nil) == 0.0
    end
  end

  describe "plan_rebase/3 (pure)" do
    test "all-new TOC with empty current → everything created, nothing matched" do
      new = [%{"name" => "Ch 1"}, %{"name" => "Ch 2"}]
      plan = TOCRebase.plan_rebase(new, [], MapSet.new())

      assert plan.matched == []
      assert length(plan.created) == 2
      assert plan.orphans == []
      assert plan.deletes == []
    end

    test "fuzzy match preserves the current chapter id" do
      current = [%{id: "id-1", name: "Chapter 1: Cells", sections: []}]
      new = [%{"name" => "Chapter 1 The Cell"}]

      plan = TOCRebase.plan_rebase(new, current, MapSet.new())

      assert [{"id-1", _old_name, _new_ch}] = plan.matched
      assert plan.deletes == []
    end

    test "chapter without attempts AND unmatched → deleted" do
      current = [%{id: "id-1", name: "Outdated Chapter", sections: []}]
      new = [%{"name" => "Different Topic Entirely"}]

      plan = TOCRebase.plan_rebase(new, current, MapSet.new())

      assert plan.deletes == current
      assert plan.orphans == []
    end

    test "chapter WITH attempts AND unmatched → orphaned, not deleted" do
      current = [%{id: "id-1", name: "Old Chapter Student Used", sections: []}]
      new = [%{"name" => "Brand New Topic"}]
      with_attempts = MapSet.new(["id-1"])

      plan = TOCRebase.plan_rebase(new, current, with_attempts)

      assert plan.orphans == current
      assert plan.deletes == []
    end

    test "one match claims only one current chapter — no double-binding" do
      current = [
        %{id: "id-1", name: "Cells", sections: []},
        %{id: "id-2", name: "Cell Biology", sections: []}
      ]

      # Only one new chapter that looks like both — should pick one,
      # leave the other for delete/orphan handling.
      new = [%{"name" => "Cells"}]

      plan = TOCRebase.plan_rebase(new, current, MapSet.new())

      assert length(plan.matched) == 1
      # The un-claimed one falls into deletes (no attempts).
      assert length(plan.deletes) == 1
    end
  end

  describe "propose/3" do
    test "inserts a DiscoveredTOC row with the computed score" do
      course = create_course()

      {:ok, toc} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: [
            %{"name" => "Ch 1", "sections" => ["1.1"]},
            %{"name" => "Ch 2"}
          ],
          ocr_char_count: 50_000
        })

      assert toc.chapter_count == 2
      assert toc.source == "textbook_full"
      assert toc.score > 0
      # Not yet applied
      assert is_nil(toc.applied_at)
    end
  end

  describe "compare/2" do
    test ":no_current when there's no prior applied TOC" do
      course = create_course()

      {:ok, new} =
        TOCRebase.propose(course.id, "web", %{chapters: [%{"name" => "a"}], ocr_char_count: 100})

      assert TOCRebase.compare(new, nil) == :no_current
    end

    test ":current_better_or_equal when new scores lower" do
      course = create_course()

      {:ok, high} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: Enum.map(1..20, &%{"name" => "Ch #{&1}"}),
          ocr_char_count: 50_000
        })

      {:ok, low} =
        TOCRebase.propose(course.id, "web", %{chapters: [%{"name" => "a"}], ocr_char_count: 100})

      # high was inserted first — mark it applied so compare/2 sees it as current.
      {:ok, _} = TOCRebase.apply(high, course.id)
      current = TOCRebase.current(course.id)

      assert TOCRebase.compare(low, current) == :current_better_or_equal
    end

    test ":insufficient_gain when improvement is below 20% gate" do
      course = create_course()
      chapters_current = Enum.map(1..10, &%{"name" => "Ch #{&1}"})
      chapters_new = Enum.map(1..11, &%{"name" => "Ch #{&1}"})

      {:ok, cur} =
        TOCRebase.propose(course.id, "web", %{chapters: chapters_current, ocr_char_count: 5_000})

      {:ok, _} = TOCRebase.apply(cur, course.id)
      current = TOCRebase.current(course.id)

      {:ok, new} =
        TOCRebase.propose(course.id, "web", %{chapters: chapters_new, ocr_char_count: 5_500})

      assert TOCRebase.compare(new, current) == :insufficient_gain
    end

    test ":new_better when source authority jumps (web → textbook_full)" do
      course = create_course()
      chapters = Enum.map(1..16, &%{"name" => "Ch #{&1}"})

      {:ok, web} =
        TOCRebase.propose(course.id, "web", %{chapters: chapters, ocr_char_count: 5_000})

      {:ok, _} = TOCRebase.apply(web, course.id)
      current = TOCRebase.current(course.id)

      rich_chapters = Enum.map(1..42, &%{"name" => "Ch #{&1}"})

      {:ok, better} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: rich_chapters,
          ocr_char_count: 100_000
        })

      assert TOCRebase.compare(better, current) == :new_better
    end
  end

  describe "apply/2 — attempt preservation" do
    test "keeps chapter_id of matched chapters (student's attempts still valid)" do
      course = create_course()
      user_role = create_user_role()

      old_chapter = create_chapter(course, "Chapter 1: Cells", 1)
      _q = create_question_with_attempt(course, old_chapter, user_role)

      {:ok, new_toc} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: [%{"name" => "Chapter 1 The Cell"}, %{"name" => "Chapter 2 Energy"}],
          ocr_char_count: 50_000
        })

      {:ok, stats} = TOCRebase.apply(new_toc, course.id)
      assert stats.kept == 1
      assert stats.created == 1
      assert stats.orphaned == 0
      assert stats.deleted == 0
      # One brand-new chapter was created — its id comes back so the worker
      # can target question generation at just that chapter.
      assert [_new_id] = stats.new_chapter_ids

      # The old chapter_id must still exist (with its question_attempts intact).
      reloaded = Courses.list_chapters_by_course(course.id)
      assert Enum.any?(reloaded, &(&1.id == old_chapter.id))

      # It got renamed to the new TOC's name.
      kept = Enum.find(reloaded, &(&1.id == old_chapter.id))
      assert kept.name == "Chapter 1 The Cell"
    end

    test "orphans chapters with attempts that don't match the new TOC" do
      course = create_course()
      user_role = create_user_role()

      old_ch = create_chapter(course, "Legacy Topic Not In Textbook", 1)
      create_question_with_attempt(course, old_ch, user_role)

      {:ok, new_toc} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: [%{"name" => "Brand New Chapter"}],
          ocr_char_count: 50_000
        })

      {:ok, %{orphaned: 1, deleted: 0}} = TOCRebase.apply(new_toc, course.id)

      # Orphan survives with a flag.
      reloaded = Courses.get_chapter!(old_ch.id)
      assert reloaded.orphaned_at != nil
    end

    test "deletes chapters that have no attempts and no match" do
      course = create_course()
      empty = create_chapter(course, "Deprecated Topic", 1)

      {:ok, new_toc} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: [%{"name" => "Totally Different"}],
          ocr_char_count: 50_000
        })

      {:ok, %{deleted: 1}} = TOCRebase.apply(new_toc, course.id)

      assert_raise Ecto.NoResultsError, fn -> Courses.get_chapter!(empty.id) end
    end

    test "marks previous TOC superseded when a new one is applied" do
      course = create_course()

      {:ok, v1} =
        TOCRebase.propose(course.id, "web", %{
          chapters: [%{"name" => "A"}],
          ocr_char_count: 1000
        })

      {:ok, _} = TOCRebase.apply(v1, course.id)

      {:ok, v2} =
        TOCRebase.propose(course.id, "textbook_full", %{
          chapters: [%{"name" => "A"}, %{"name" => "B"}],
          ocr_char_count: 60_000
        })

      {:ok, _} = TOCRebase.apply(v2, course.id)

      current = TOCRebase.current(course.id)
      assert current.id == v2.id
      assert current.source == "textbook_full"

      # v1 should now have a superseded_at.
      old = FunSheep.Repo.get(DiscoveredTOC, v1.id)
      assert old.superseded_at != nil
    end
  end
end
