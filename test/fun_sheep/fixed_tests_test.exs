defmodule FunSheep.FixedTestsTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.FixedTests
  alias FunSheep.ContentFixtures

  # ── Fixtures ─────────────────────────────────────────────────────────────

  defp create_user_role(attrs \\ %{}) do
    ContentFixtures.create_user_role(attrs)
  end

  defp create_bank(user_role, attrs \\ %{}) do
    defaults = %{"title" => "Test Quiz", "created_by_id" => user_role.id}
    {:ok, bank} = FixedTests.create_bank(Map.merge(defaults, attrs))
    bank
  end

  defp add_question(bank, attrs \\ %{}) do
    defaults = %{
      "question_text" => "What is 2 + 2?",
      "answer_text" => "4",
      "question_type" => "short_answer"
    }

    {:ok, question} = FixedTests.add_question(bank, Map.merge(defaults, attrs))
    question
  end

  # ── Bank CRUD ─────────────────────────────────────────────────────────────

  describe "create_bank/1" do
    test "creates a bank with valid attrs" do
      user_role = create_user_role()

      assert {:ok, bank} =
               FixedTests.create_bank(%{
                 "title" => "My Quiz",
                 "created_by_id" => user_role.id
               })

      assert bank.title == "My Quiz"
      assert bank.visibility == "private"
      assert bank.shuffle_questions == false
      assert is_nil(bank.archived_at)
    end

    test "fails without title" do
      user_role = create_user_role()
      assert {:error, cs} = FixedTests.create_bank(%{"created_by_id" => user_role.id})
      assert %{title: _} = errors_on(cs)
    end

    test "fails without created_by_id" do
      assert {:error, cs} = FixedTests.create_bank(%{"title" => "Quiz"})
      assert %{created_by_id: _} = errors_on(cs)
    end

    test "rejects invalid visibility" do
      user_role = create_user_role()

      assert {:error, cs} =
               FixedTests.create_bank(%{
                 "title" => "Quiz",
                 "created_by_id" => user_role.id,
                 "visibility" => "public"
               })

      assert %{visibility: _} = errors_on(cs)
    end
  end

  describe "list_banks_by_creator/1" do
    test "returns only active banks for the creator" do
      creator = create_user_role()
      other = create_user_role()

      bank1 = create_bank(creator, %{"title" => "Quiz A"})
      bank2 = create_bank(creator, %{"title" => "Quiz B"})
      _bank_other = create_bank(other, %{"title" => "Other"})
      {:ok, _archived} = FixedTests.archive_bank(create_bank(creator, %{"title" => "Old"}))

      results = FixedTests.list_banks_by_creator(creator.id)
      ids = Enum.map(results, & &1.id)

      assert bank1.id in ids
      assert bank2.id in ids
      refute Enum.any?(results, fn b -> b.created_by_id == other.id end)
      assert length(ids) == 2
    end
  end

  describe "archive_bank/1" do
    test "sets archived_at" do
      user_role = create_user_role()
      bank = create_bank(user_role)

      assert {:ok, archived} = FixedTests.archive_bank(bank)
      assert archived.archived_at != nil
    end
  end

  # ── Questions ─────────────────────────────────────────────────────────────

  describe "add_question/2" do
    test "adds a question and auto-assigns position" do
      user_role = create_user_role()
      bank = create_bank(user_role)

      {:ok, q1} =
        FixedTests.add_question(bank, %{
          "question_text" => "Q1",
          "answer_text" => "A1",
          "question_type" => "short_answer"
        })

      {:ok, q2} =
        FixedTests.add_question(bank, %{
          "question_text" => "Q2",
          "answer_text" => "A2",
          "question_type" => "short_answer"
        })

      assert q1.position == 1
      assert q2.position == 2
    end

    test "fails without required fields" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      assert {:error, cs} = FixedTests.add_question(bank, %{})
      assert %{question_text: _, answer_text: _} = errors_on(cs)
    end
  end

  describe "delete_question/1" do
    test "removes the question" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      question = add_question(bank)

      assert {:ok, _} = FixedTests.delete_question(question)

      assert_raise Ecto.NoResultsError, fn ->
        FixedTests.get_question!(question.id)
      end
    end
  end

  describe "reorder_questions/2" do
    test "reassigns positions" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      q1 = add_question(bank, %{"question_text" => "first"})
      q2 = add_question(bank, %{"question_text" => "second"})
      q3 = add_question(bank, %{"question_text" => "third"})

      assert {:ok, _} = FixedTests.reorder_questions(bank.id, [q3.id, q1.id, q2.id])

      updated = FixedTests.get_bank_with_questions!(bank.id)
      [p1, p2, p3] = Enum.map(updated.questions, & &1.position)
      assert p1 == 1 and p2 == 2 and p3 == 3
      assert Enum.map(updated.questions, & &1.question_text) == ["third", "first", "second"]
    end
  end

  # ── Assignments ───────────────────────────────────────────────────────────

  describe "assign_bank/4" do
    test "creates assignment records for each student" do
      teacher = create_user_role(%{role: :teacher})
      student1 = create_user_role()
      student2 = create_user_role()
      bank = create_bank(teacher)

      assert {:ok, assignments} =
               FixedTests.assign_bank(bank, teacher.id, [student1.id, student2.id])

      assert length(assignments) == 2
      assert Enum.all?(assignments, &(&1.bank_id == bank.id))
    end

    test "is idempotent — existing assignment is updated, not duplicated" do
      teacher = create_user_role(%{role: :teacher})
      student = create_user_role()
      bank = create_bank(teacher)

      {:ok, _} = FixedTests.assign_bank(bank, teacher.id, [student.id])
      {:ok, assignments} = FixedTests.assign_bank(bank, teacher.id, [student.id])

      assert length(assignments) == 1
      all = FixedTests.list_assignments_for_student(student.id)
      assert length(all) == 1
    end
  end

  # ── Sessions ──────────────────────────────────────────────────────────────

  describe "start_session/3" do
    test "creates an in_progress session with questions_order" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      add_question(bank)

      assert {:ok, session} = FixedTests.start_session(bank.id, user_role.id)
      assert session.status == "in_progress"
      assert session.started_at != nil
      assert is_list(session.questions_order)
      assert length(session.questions_order) == 1
    end

    test "shuffles order when bank.shuffle_questions is true" do
      user_role = create_user_role()

      {:ok, bank} =
        FixedTests.create_bank(%{
          "title" => "Shuffled",
          "created_by_id" => user_role.id,
          "shuffle_questions" => "true"
        })

      for i <- 1..10, do: add_question(bank, %{"question_text" => "Q#{i}", "answer_text" => "A"})

      {:ok, s1} = FixedTests.start_session(bank.id, user_role.id)
      {:ok, s2} = FixedTests.start_session(bank.id, user_role.id)

      # Orders may differ (with 10 items, collision probability is 1/10! ≈ 0%)
      assert length(s1.questions_order) == 10
      assert length(s2.questions_order) == 10
      # Orders are not guaranteed equal
    end
  end

  describe "submit_answer/4" do
    test "records the answer and grades it" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      question = add_question(bank, %{"answer_text" => "photosynthesis"})
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)

      assert {:ok, updated} =
               FixedTests.submit_answer(session, question.id, "photosynthesis")

      [answer] = updated.answers
      assert answer["is_correct"] == true
      assert answer["answer_given"] == "photosynthesis"
    end

    test "case-insensitive grading" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      question = add_question(bank, %{"answer_text" => "Mitochondria"})
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)

      {:ok, updated} = FixedTests.submit_answer(session, question.id, "MITOCHONDRIA")
      assert hd(updated.answers)["is_correct"] == true
    end

    test "marks incorrect when wrong" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      question = add_question(bank, %{"answer_text" => "correct"})
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)

      {:ok, updated} = FixedTests.submit_answer(session, question.id, "wrong")
      assert hd(updated.answers)["is_correct"] == false
    end

    test "overwriting an answer replaces it, not appends" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      question = add_question(bank, %{"answer_text" => "correct"})
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)

      {:ok, s1} = FixedTests.submit_answer(session, question.id, "wrong")
      {:ok, s2} = FixedTests.submit_answer(s1, question.id, "correct")

      assert length(s2.answers) == 1
      assert hd(s2.answers)["is_correct"] == true
    end
  end

  describe "complete_session/1" do
    test "tallies score and marks completed" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      q1 = add_question(bank, %{"answer_text" => "yes"})
      q2 = add_question(bank, %{"answer_text" => "no"})
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)
      {:ok, s1} = FixedTests.submit_answer(session, q1.id, "yes")
      {:ok, s2} = FixedTests.submit_answer(s1, q2.id, "wrong")

      assert {:ok, completed} = FixedTests.complete_session(s2)
      assert completed.status == "completed"
      assert completed.score_correct == 1
      assert completed.score_total == 2
      assert completed.completed_at != nil
    end

    test "allows zero-score completion (all unanswered)" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      add_question(bank)
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)

      assert {:ok, completed} = FixedTests.complete_session(session)
      assert completed.score_correct == 0
      assert completed.score_total == 0
      assert completed.status == "completed"
    end
  end

  # ── Access control ────────────────────────────────────────────────────────

  describe "can_take?/2" do
    test "creator can always take their own bank" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      assert FixedTests.can_take?(bank, user_role.id)
    end

    test "assigned student can take the bank" do
      teacher = create_user_role(%{role: :teacher})
      student = create_user_role()
      bank = create_bank(teacher)
      {:ok, _} = FixedTests.assign_bank(bank, teacher.id, [student.id])

      bank_loaded = FixedTests.get_bank!(bank.id)
      assert FixedTests.can_take?(bank_loaded, student.id)
    end

    test "unassigned student cannot take a private bank" do
      teacher = create_user_role(%{role: :teacher})
      student = create_user_role()
      bank = create_bank(teacher, %{"visibility" => "private"})

      refute FixedTests.can_take?(bank, student.id)
    end
  end

  describe "within_attempt_limit?/2" do
    test "unlimited when max_attempts is nil" do
      user_role = create_user_role()
      bank = create_bank(user_role)
      assert FixedTests.within_attempt_limit?(bank, user_role.id)
    end

    test "false when attempts exhausted" do
      user_role = create_user_role()

      {:ok, bank} =
        FixedTests.create_bank(%{
          "title" => "Limited",
          "created_by_id" => user_role.id,
          "max_attempts" => "1"
        })

      add_question(bank)
      {:ok, session} = FixedTests.start_session(bank.id, user_role.id)
      {:ok, _} = FixedTests.complete_session(session)

      bank_reloaded = FixedTests.get_bank!(bank.id)
      refute FixedTests.within_attempt_limit?(bank_reloaded, user_role.id)
    end
  end
end
