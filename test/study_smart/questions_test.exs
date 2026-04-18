defmodule StudySmart.QuestionsTest do
  use StudySmart.DataCase, async: true

  alias StudySmart.Courses
  alias StudySmart.Questions

  defp create_course do
    {:ok, course} = Courses.create_course(%{name: "Test Course", subject: "Math", grade: "10"})
    course
  end

  defp create_question(course, attrs \\ %{}) do
    defaults = %{
      content: "What is 2 + 2?",
      answer: "4",
      question_type: :multiple_choice,
      difficulty: :medium,
      course_id: course.id
    }

    {:ok, question} = Questions.create_question(Map.merge(defaults, attrs))
    question
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
  end
end
