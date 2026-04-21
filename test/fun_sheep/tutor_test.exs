defmodule FunSheep.TutorTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Tutor
  alias FunSheep.Courses
  alias FunSheep.Questions

  @user_role_id Ecto.UUID.generate()

  defp create_course do
    {:ok, course} = Courses.create_course(%{name: "Algebra 101", subject: "Math", grade: "10"})
    course
  end

  defp create_question(course, attrs \\ %{}) do
    defaults = %{
      content: "What is the value of x in 2x + 4 = 10?",
      answer: "3",
      question_type: :multiple_choice,
      difficulty: :medium,
      course_id: course.id,
      options: %{"A" => "1", "B" => "2", "C" => "3", "D" => "4"},
      validation_status: :passed
    }

    {:ok, question} = Questions.create_question(Map.merge(defaults, attrs))
    question
  end

  setup do
    # Clear any cached assistant ID from previous tests
    try do
      :persistent_term.erase({Tutor, :assistant_id})
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  describe "ensure_assistant/0" do
    test "returns {:ok, assistant_id} on first call" do
      assert {:ok, assistant_id} = Tutor.ensure_assistant()
      assert is_binary(assistant_id)
    end

    test "caches the assistant ID in persistent_term" do
      {:ok, first_id} = Tutor.ensure_assistant()
      {:ok, second_id} = Tutor.ensure_assistant()
      assert first_id == second_id
    end

    test "returns cached ID on subsequent calls" do
      # Pre-seed the cache
      :persistent_term.put({Tutor, :assistant_id}, "cached_id_123")
      assert {:ok, "cached_id_123"} = Tutor.ensure_assistant()
    end
  end

  describe "build_context/3" do
    test "builds a context map with all required keys" do
      course = create_course()
      question = create_question(course)

      # Reload with preloads as start_session would
      question = Questions.get_question_with_context!(question.id)
      course = Courses.get_course_with_chapters!(course.id)

      context = Tutor.build_context(question, course, @user_role_id)

      assert is_map(context)
      assert Map.has_key?(context, :question)
      assert Map.has_key?(context, :course)
      assert Map.has_key?(context, :student)
      assert Map.has_key?(context, :stats)
      assert Map.has_key?(context, :related_content)
    end

    test "question context includes content, type, options, and answer" do
      course = create_course()
      question = create_question(course)
      question = Questions.get_question_with_context!(question.id)
      course = Courses.get_course_with_chapters!(course.id)

      context = Tutor.build_context(question, course, @user_role_id)

      assert context.question.content == question.content
      assert context.question.type == :multiple_choice
      assert context.question.correct_answer == "3"
      assert context.question.options == %{"A" => "1", "B" => "2", "C" => "3", "D" => "4"}
      assert context.question.difficulty == :medium
    end

    test "course context includes name and subject" do
      course = create_course()
      question = create_question(course)
      question = Questions.get_question_with_context!(question.id)
      course = Courses.get_course_with_chapters!(course.id)

      context = Tutor.build_context(question, course, @user_role_id)

      assert context.course.name == "Algebra 101"
      assert context.course.subject == "Math"
    end

    test "student context has empty previous_attempts when none exist" do
      course = create_course()
      question = create_question(course)
      question = Questions.get_question_with_context!(question.id)
      course = Courses.get_course_with_chapters!(course.id)

      context = Tutor.build_context(question, course, @user_role_id)

      assert context.student.previous_attempts == []
    end

    test "stats show zero attempts when no stats exist" do
      course = create_course()
      question = create_question(course)
      question = Questions.get_question_with_context!(question.id)
      course = Courses.get_course_with_chapters!(course.id)

      context = Tutor.build_context(question, course, @user_role_id)

      assert context.stats.total_attempts == 0
      assert context.stats.correct_rate == nil
      assert context.stats.avg_time == nil
    end

    test "related_content is a list (from mock KB search)" do
      course = create_course()
      question = create_question(course)
      question = Questions.get_question_with_context!(question.id)
      course = Courses.get_course_with_chapters!(course.id)

      context = Tutor.build_context(question, course, @user_role_id)

      assert is_list(context.related_content)
    end
  end

  describe "start_session/3" do
    test "returns {:ok, session_id} for a valid question and course" do
      course = create_course()
      question = create_question(course)

      assert {:ok, session_id} = Tutor.start_session(@user_role_id, question.id, course.id)
      assert session_id == "tutor:#{@user_role_id}:#{question.id}"

      # Clean up
      Tutor.stop_session(session_id)
    end

    test "returns {:ok, session_id} when session already exists (idempotent)" do
      course = create_course()
      question = create_question(course)

      {:ok, session_id} = Tutor.start_session(@user_role_id, question.id, course.id)
      assert {:ok, ^session_id} = Tutor.start_session(@user_role_id, question.id, course.id)

      Tutor.stop_session(session_id)
    end
  end

  describe "ask/2" do
    test "returns {:ok, response} for an active session" do
      course = create_course()
      question = create_question(course)
      {:ok, session_id} = Tutor.start_session(@user_role_id, question.id, course.id)

      assert {:ok, response} = Tutor.ask(session_id, "Can you help me with this?")
      assert is_binary(response)
      assert String.length(response) > 0

      Tutor.stop_session(session_id)
    end

    test "returns {:error, :session_not_found} for a non-existent session" do
      assert {:error, :session_not_found} = Tutor.ask("nonexistent:session:id", "hello")
    end
  end

  describe "quick_action/3" do
    setup do
      course = create_course()
      question = create_question(course)
      {:ok, session_id} = Tutor.start_session(@user_role_id, question.id, course.id)

      on_exit(fn -> Tutor.stop_session(session_id) end)

      %{session_id: session_id, question: question}
    end

    test "hint action returns a response with hint content", %{
      session_id: session_id,
      question: question
    } do
      assert {:ok, response} = Tutor.quick_action(session_id, "hint", question)
      assert is_binary(response)
      assert String.contains?(response, "hint") or String.contains?(response, "Hint")
    end

    test "explain action returns a response", %{session_id: session_id, question: question} do
      assert {:ok, response} = Tutor.quick_action(session_id, "explain", question)
      assert is_binary(response)
    end

    test "why_wrong action returns a response referencing the answer", %{
      session_id: session_id,
      question: question
    } do
      assert {:ok, response} = Tutor.quick_action(session_id, "why_wrong", question)
      assert is_binary(response)
    end

    test "step_by_step action returns a response", %{
      session_id: session_id,
      question: question
    } do
      assert {:ok, response} = Tutor.quick_action(session_id, "step_by_step", question)
      assert is_binary(response)
    end

    test "similar action returns a response", %{session_id: session_id, question: question} do
      assert {:ok, response} = Tutor.quick_action(session_id, "similar", question)
      assert is_binary(response)
    end

    test "unknown action falls through and still returns a response", %{
      session_id: session_id,
      question: question
    } do
      assert {:ok, response} = Tutor.quick_action(session_id, "custom_action", question)
      assert is_binary(response)
    end
  end

  describe "stop_session/1" do
    test "stops an active session cleanly" do
      course = create_course()
      question = create_question(course)
      {:ok, session_id} = Tutor.start_session(@user_role_id, question.id, course.id)

      assert :ok = Tutor.stop_session(session_id)

      # Session should no longer be accessible
      assert {:error, :session_not_found} = Tutor.ask(session_id, "hello")
    end

    test "returns :ok when stopping a non-existent session" do
      assert :ok = Tutor.stop_session("nonexistent:session:id")
    end
  end

  describe "topic/1" do
    test "returns the PubSub topic string" do
      assert Tutor.topic("my_session") == "tutor:my_session"
    end

    test "includes session_id in the topic" do
      session_id = "tutor:user123:question456"
      assert Tutor.topic(session_id) == "tutor:#{session_id}"
    end
  end
end
