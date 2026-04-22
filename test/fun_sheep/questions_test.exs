defmodule FunSheep.QuestionsTest do
  use FunSheep.DataCase, async: true
  use Oban.Testing, repo: FunSheep.Repo

  alias FunSheep.Courses
  alias FunSheep.Questions

  defp create_course do
    {:ok, course} = Courses.create_course(%{name: "Test Course", subject: "Math", grade: "10"})
    course
  end

  defp create_question(course, attrs \\ %{}) do
    # Auto-attach section + trusted classification so the created question is
    # adaptive-eligible (North Star I-1). Tests that want an untagged question
    # override :section_id / :classification_status.
    {chapter_id, section_id} = ensure_section(course, attrs[:chapter_id])

    defaults = %{
      content: "What is 2 + 2?",
      answer: "4",
      question_type: :multiple_choice,
      difficulty: :medium,
      course_id: course.id,
      chapter_id: chapter_id,
      section_id: section_id,
      classification_status: :admin_reviewed,
      validation_status: :passed
    }

    {:ok, question} = Questions.create_question(Map.merge(defaults, attrs))
    question
  end

  defp ensure_section(course, nil) do
    {:ok, ch} =
      Courses.create_chapter(%{
        name: "Auto Chapter #{System.unique_integer([:positive])}",
        position: 1,
        course_id: course.id
      })

    {:ok, sec} =
      Courses.create_section(%{name: "Auto Section", position: 1, chapter_id: ch.id})

    {ch.id, sec.id}
  end

  defp ensure_section(_course, chapter_id) do
    {:ok, sec} =
      Courses.create_section(%{
        name: "Auto Section #{System.unique_integer([:positive])}",
        position: 1,
        chapter_id: chapter_id
      })

    {chapter_id, sec.id}
  end

  describe "create_question/1" do
    test "creates with valid attrs" do
      course = create_course()

      assert {:ok, question} =
               Questions.create_question(%{
                 content: "What is 1+1?",
                 answer: "2",
                 question_type: :short_answer,
                 course_id: course.id,
                 difficulty: :easy
               })

      assert question.content == "What is 1+1?"
      assert question.question_type == :short_answer
      assert question.difficulty == :easy
    end

    test "fails without required fields" do
      assert {:error, changeset} = Questions.create_question(%{})

      assert %{content: _, answer: _, question_type: _, difficulty: _, course_id: _} =
               errors_on(changeset)
    end

    test "validates question_type enum" do
      course = create_course()

      assert {:error, changeset} =
               Questions.create_question(%{
                 content: "Test",
                 answer: "Answer",
                 question_type: :invalid_type,
                 difficulty: :easy,
                 course_id: course.id
               })

      assert %{question_type: _} = errors_on(changeset)
    end

    test "validates difficulty enum" do
      course = create_course()

      assert {:error, changeset} =
               Questions.create_question(%{
                 content: "Test",
                 answer: "Answer",
                 question_type: :multiple_choice,
                 course_id: course.id,
                 difficulty: :impossible
               })

      assert %{difficulty: _} = errors_on(changeset)
    end
  end

  describe "update_question/2" do
    test "updates with valid attrs" do
      course = create_course()
      question = create_question(course)

      assert {:ok, updated} = Questions.update_question(question, %{content: "Updated question"})
      assert updated.content == "Updated question"
    end
  end

  describe "delete_question/1" do
    test "deletes the question" do
      course = create_course()
      question = create_question(course)

      assert {:ok, _} = Questions.delete_question(question)
      assert_raise Ecto.NoResultsError, fn -> Questions.get_question!(question.id) end
    end
  end

  describe "list_questions_by_course/2" do
    test "returns all questions for a course" do
      course = create_course()
      create_question(course, %{content: "Q1"})
      create_question(course, %{content: "Q2"})

      questions = Questions.list_questions_by_course(course.id)
      assert length(questions) == 2
    end

    test "filters by chapter_id" do
      course = create_course()
      {:ok, ch1} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})
      {:ok, ch2} = Courses.create_chapter(%{name: "Ch 2", position: 2, course_id: course.id})

      create_question(course, %{content: "Q1", chapter_id: ch1.id})
      create_question(course, %{content: "Q2", chapter_id: ch2.id})

      questions = Questions.list_questions_by_course(course.id, %{"chapter_id" => ch1.id})
      assert length(questions) == 1
      assert hd(questions).content == "Q1"
    end

    test "filters by difficulty" do
      course = create_course()
      create_question(course, %{content: "Easy Q", difficulty: :easy})
      create_question(course, %{content: "Hard Q", difficulty: :hard})

      questions = Questions.list_questions_by_course(course.id, %{"difficulty" => "easy"})
      assert length(questions) == 1
      assert hd(questions).content == "Easy Q"
    end

    test "filters by question_type" do
      course = create_course()
      create_question(course, %{content: "MC", question_type: :multiple_choice})
      create_question(course, %{content: "TF", question_type: :true_false})

      questions =
        Questions.list_questions_by_course(course.id, %{"question_type" => "true_false"})

      assert length(questions) == 1
      assert hd(questions).content == "TF"
    end

    test "returns empty list for course with no questions" do
      course = create_course()
      assert Questions.list_questions_by_course(course.id) == []
    end

    test "hides pending, needs_review, and failed questions from students" do
      course = create_course()
      create_question(course, %{content: "Passed", validation_status: :passed})
      create_question(course, %{content: "Pending", validation_status: :pending})
      create_question(course, %{content: "Review", validation_status: :needs_review})
      create_question(course, %{content: "Failed", validation_status: :failed})

      questions = Questions.list_questions_by_course(course.id)
      assert length(questions) == 1
      assert hd(questions).content == "Passed"
    end

    test "count_questions_by_course only counts passed questions" do
      course = create_course()
      create_question(course, %{content: "Passed", validation_status: :passed})
      create_question(course, %{content: "Pending", validation_status: :pending})
      create_question(course, %{content: "Failed", validation_status: :failed})

      assert Questions.count_questions_by_course(course.id) == 1
      assert Questions.count_all_questions_by_course(course.id) == 3
    end
  end

  describe "requeue_pending_validations/1" do
    # Use :manual so we can assert the job was enqueued without actually
    # running the validator (which would hit Interactor).
    test "enqueues validation jobs for every :pending question and returns count" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()
        create_question(course, %{content: "pend1", validation_status: :pending})
        create_question(course, %{content: "pend2", validation_status: :pending})
        create_question(course, %{content: "pass1", validation_status: :passed})

        {:ok, count} = Questions.requeue_pending_validations(course.id)

        assert count == 2
        assert_enqueued(worker: FunSheep.Workers.QuestionValidationWorker, queue: :ai)
      end)
    end

    test "returns 0 when nothing is pending" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()
        create_question(course, %{content: "p", validation_status: :passed})

        assert {:ok, 0} = Questions.requeue_pending_validations(course.id)
      end)
    end

    test "scopes to the given course id" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course1 = create_course()
        course2 = create_course()
        create_question(course1, %{content: "c1", validation_status: :pending})
        create_question(course2, %{content: "c2", validation_status: :pending})

        assert {:ok, 1} = Questions.requeue_pending_validations(course1.id)
      end)
    end
  end

  describe "count_by_validation_status/1" do
    test "returns counts bucketed by status with zero-fill" do
      course = create_course()
      create_question(course, %{content: "p1", validation_status: :passed})
      create_question(course, %{content: "p2", validation_status: :passed})
      create_question(course, %{content: "r1", validation_status: :needs_review})
      create_question(course, %{content: "f1", validation_status: :failed})

      counts = Questions.count_by_validation_status(course.id)

      assert counts == %{pending: 0, passed: 2, needs_review: 1, failed: 1}
    end

    test "returns all-zero map for a course with no questions" do
      course = create_course()

      assert Questions.count_by_validation_status(course.id) == %{
               pending: 0,
               passed: 0,
               needs_review: 0,
               failed: 0
             }
    end
  end

  describe "list_questions_needing_review/1" do
    test "returns only needs_review questions" do
      course = create_course()
      create_question(course, %{content: "Passed", validation_status: :passed})
      create_question(course, %{content: "Review me", validation_status: :needs_review})
      create_question(course, %{content: "Failed", validation_status: :failed})

      results = Questions.list_questions_needing_review(course.id)
      assert length(results) == 1
      assert hd(results).content == "Review me"
    end
  end

  describe "list_questions_for_quick_test/3 — deduplication across sessions" do
    # Regression: clairehyj reported seeing the same questions 4 times in a
    # row. Root cause was that the quick-test query applied pure randomization
    # with no memory of what the user had already seen.

    alias FunSheep.ContentFixtures

    defp create_attempt(user_role, question, opts) do
      is_correct = Keyword.get(opts, :is_correct, true)
      inserted_at = Keyword.get(opts, :inserted_at, DateTime.utc_now())

      {:ok, attempt} =
        Questions.create_question_attempt(%{
          user_role_id: user_role.id,
          question_id: question.id,
          is_correct: is_correct,
          answer_given: "x"
        })

      # Backdate the attempt if requested — the default DB now() is coarse
      # and we need deterministic recency ordering in tests.
      if inserted_at != attempt.inserted_at do
        attempt
        |> Ecto.Changeset.change(%{inserted_at: inserted_at})
        |> FunSheep.Repo.update!()
      else
        attempt
      end
    end

    test "excludes recently-attempted questions when pool is large enough" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()

      # Pool of 6 questions, session limit of 3. First session returns 3; the
      # second must return the other 3, never repeating.
      questions = for i <- 1..6, do: create_question(course, %{content: "Q#{i}"})

      first = Questions.list_questions_for_quick_test(user_role.id, course.id, 3)
      assert length(first) == 3

      # Record attempts on everything we served.
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Enum.each(first, fn q -> create_attempt(user_role, q, inserted_at: now) end)

      second = Questions.list_questions_for_quick_test(user_role.id, course.id, 3)
      assert length(second) == 3

      first_ids = MapSet.new(first, & &1.id)
      second_ids = MapSet.new(second, & &1.id)
      assert MapSet.disjoint?(first_ids, second_ids)

      all_ids = MapSet.new(questions, & &1.id)
      assert MapSet.union(first_ids, second_ids) == all_ids
    end

    test "backfills when the pool is smaller than the session limit" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()

      # Only 3 questions available but we ask for 5. User has already
      # attempted all 3 — dedup would return 0, so backfill must fill.
      questions = for i <- 1..3, do: create_question(course, %{content: "Q#{i}"})
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      Enum.each(questions, fn q -> create_attempt(user_role, q, inserted_at: past) end)

      result = Questions.list_questions_for_quick_test(user_role.id, course.id, 5)

      # With only 3 distinct questions, we can at most return 3 — but the
      # user MUST get something (not an empty list).
      assert length(result) == 3
      result_ids = MapSet.new(result, & &1.id)
      expected_ids = MapSet.new(questions, & &1.id)
      assert result_ids == expected_ids
    end

    test "treats a user with no attempts the same as before the fix" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()
      for i <- 1..5, do: create_question(course, %{content: "Q#{i}"})

      result = Questions.list_questions_for_quick_test(user_role.id, course.id, 3)
      assert length(result) == 3
    end
  end

  describe "list_weak_questions/4 — deduplication across sessions" do
    alias FunSheep.ContentFixtures

    defp create_wrong_attempt(user_role, question, inserted_at) do
      {:ok, attempt} =
        Questions.create_question_attempt(%{
          user_role_id: user_role.id,
          question_id: question.id,
          is_correct: false,
          answer_given: "wrong"
        })

      attempt
      |> Ecto.Changeset.change(%{inserted_at: inserted_at})
      |> FunSheep.Repo.update!()
    end

    test "excludes recently-seen weak questions across consecutive sessions" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()

      questions = for i <- 1..6, do: create_question(course, %{content: "Weak #{i}"})
      # Seed a wrong attempt on each question far enough in the past that
      # they are all eligible for practice but none are "recently seen" yet.
      far_past =
        DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second)

      Enum.each(questions, fn q -> create_wrong_attempt(user_role, q, far_past) end)

      first = Questions.list_weak_questions(user_role.id, course.id, nil, 3)
      assert length(first) == 3

      # Simulate the user practicing those 3 just now (any outcome counts as
      # "recently seen" for dedup purposes — here we keep them wrong).
      recent = DateTime.utc_now() |> DateTime.truncate(:second)
      Enum.each(first, fn q -> create_wrong_attempt(user_role, q, recent) end)

      second = Questions.list_weak_questions(user_role.id, course.id, nil, 3)
      assert length(second) == 3

      first_ids = MapSet.new(first, & &1.id)
      second_ids = MapSet.new(second, & &1.id)
      assert MapSet.disjoint?(first_ids, second_ids)
    end

    test "backfills when all weak questions are recently seen" do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()

      # Only 2 weak questions; ask for 5. Both are recently seen, but the
      # user must still get both back (not an empty list).
      questions = for i <- 1..2, do: create_question(course, %{content: "Weak #{i}"})
      recent = DateTime.utc_now() |> DateTime.truncate(:second)
      Enum.each(questions, fn q -> create_wrong_attempt(user_role, q, recent) end)

      result = Questions.list_weak_questions(user_role.id, course.id, nil, 5)

      assert length(result) == 2
      assert MapSet.new(result, & &1.id) == MapSet.new(questions, & &1.id)
    end
  end
end
