defmodule FunSheep.EssaysTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Essays
  alias FunSheep.Essays.{EssayDraft, EssayRubricTemplate}
  alias FunSheep.ContentFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_rubric_template(attrs \\ %{}) do
    defaults = %{
      name: "Test Rubric",
      exam_type: "test_#{System.unique_integer([:positive])}",
      max_score: 10,
      mastery_threshold_ratio: 0.67,
      criteria: [
        %{"name" => "Thesis", "max_points" => 5, "description" => "Clear thesis"},
        %{"name" => "Evidence", "max_points" => 5, "description" => "Good evidence"}
      ]
    }

    {:ok, template} =
      %EssayRubricTemplate{}
      |> EssayRubricTemplate.changeset(Map.merge(defaults, attrs))
      |> Repo.insert()

    template
  end

  defp create_question(_user_role_id, course) do
    {:ok, question} =
      %FunSheep.Questions.Question{}
      |> FunSheep.Questions.Question.changeset(%{
        content: "Write an essay on photosynthesis.",
        answer: "See rubric",
        question_type: :essay,
        difficulty: :medium,
        course_id: course.id
      })
      |> Repo.insert()

    question
  end

  # ---------------------------------------------------------------------------
  # Rubric template CRUD
  # ---------------------------------------------------------------------------

  describe "list_rubric_templates/0" do
    test "returns all templates" do
      t1 = create_rubric_template(%{name: "A Template"})
      t2 = create_rubric_template(%{name: "B Template"})

      templates = Essays.list_rubric_templates()
      ids = Enum.map(templates, & &1.id)
      assert t1.id in ids
      assert t2.id in ids
    end
  end

  describe "get_rubric_template/1" do
    test "returns template by id" do
      template = create_rubric_template()
      assert %EssayRubricTemplate{id: id} = Essays.get_rubric_template(template.id)
      assert id == template.id
    end

    test "returns nil for unknown id" do
      assert is_nil(Essays.get_rubric_template(Ecto.UUID.generate()))
    end
  end

  describe "get_rubric_template_by_exam_type/1" do
    test "returns template by exam_type" do
      template = create_rubric_template(%{exam_type: "unique_exam_type"})
      result = Essays.get_rubric_template_by_exam_type("unique_exam_type")
      assert result.id == template.id
    end

    test "returns nil for unknown exam_type" do
      assert is_nil(Essays.get_rubric_template_by_exam_type("nonexistent"))
    end
  end

  # ---------------------------------------------------------------------------
  # Draft management
  # ---------------------------------------------------------------------------

  describe "get_or_create_draft/3" do
    setup do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()
      question = create_question(user_role.id, course)
      %{user_role: user_role, question: question}
    end

    test "creates a new draft when none exists", %{user_role: ur, question: q} do
      assert {:ok, %EssayDraft{} = draft} =
               Essays.get_or_create_draft(ur.id, q.id)

      assert draft.user_role_id == ur.id
      assert draft.question_id == q.id
      assert draft.submitted == false
      assert draft.body in ["", nil]
    end

    test "returns the existing non-submitted draft", %{user_role: ur, question: q} do
      {:ok, first_draft} = Essays.get_or_create_draft(ur.id, q.id)
      {:ok, second_draft} = Essays.get_or_create_draft(ur.id, q.id)

      assert first_draft.id == second_draft.id
    end

    test "creates a new draft after the previous one is submitted", %{user_role: ur, question: q} do
      {:ok, first_draft} = Essays.get_or_create_draft(ur.id, q.id)
      {:ok, _} = Essays.submit_draft(first_draft.id)

      {:ok, new_draft} = Essays.get_or_create_draft(ur.id, q.id)
      assert new_draft.id != first_draft.id
      assert new_draft.submitted == false
    end
  end

  describe "upsert_draft/4" do
    setup do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()
      question = create_question(user_role.id, course)
      {:ok, draft} = Essays.get_or_create_draft(user_role.id, question.id)
      %{user_role: user_role, question: question, draft: draft}
    end

    test "updates body and word_count", %{user_role: ur, question: q} do
      body = "This is a test essay. It has some words."

      assert {:ok, updated} = Essays.upsert_draft(ur.id, q.id, body)

      assert updated.body == body
      assert updated.word_count == 9
    end

    test "updates time_elapsed_seconds when provided", %{user_role: ur, question: q} do
      assert {:ok, updated} =
               Essays.upsert_draft(ur.id, q.id, "Some text", time_elapsed_seconds: 120)

      assert updated.time_elapsed_seconds == 120
    end

    test "creates a new draft if none exists yet", %{user_role: ur} do
      course2 = ContentFixtures.create_course()
      question2 = create_question(ur.id, course2)

      # No draft exists for this question yet
      assert {:ok, draft} = Essays.upsert_draft(ur.id, question2.id, "New essay content")
      assert draft.body == "New essay content"
    end

    test "uses provided word_count if given", %{user_role: ur, question: q} do
      assert {:ok, updated} =
               Essays.upsert_draft(ur.id, q.id, "hello world", word_count: 999)

      assert updated.word_count == 999
    end
  end

  describe "submit_draft/1" do
    setup do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()
      question = create_question(user_role.id, course)
      {:ok, draft} = Essays.get_or_create_draft(user_role.id, question.id)
      %{draft: draft, user_role: user_role, question: question}
    end

    test "sets submitted: true and submitted_at", %{draft: draft} do
      assert {:ok, updated} = Essays.submit_draft(draft.id)

      assert updated.submitted == true
      assert not is_nil(updated.submitted_at)
    end

    test "returns error for unknown draft id" do
      assert {:error, :not_found} = Essays.submit_draft(Ecto.UUID.generate())
    end
  end

  describe "get_active_draft/3" do
    setup do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course()
      question = create_question(user_role.id, course)
      %{user_role: user_role, question: question}
    end

    test "returns nil when no draft exists", %{user_role: ur, question: q} do
      result = Essays.get_active_draft(ur.id, q.id)
      assert is_nil(result)
    end

    test "returns draft when active draft exists", %{user_role: ur, question: q} do
      {:ok, draft} = Essays.get_or_create_draft(ur.id, q.id)
      result = Essays.get_active_draft(ur.id, q.id)
      assert result.id == draft.id
    end

    test "returns nil after draft is submitted", %{user_role: ur, question: q} do
      {:ok, draft} = Essays.get_or_create_draft(ur.id, q.id)
      {:ok, _} = Essays.submit_draft(draft.id)

      result = Essays.get_active_draft(ur.id, q.id)
      assert is_nil(result)
    end
  end
end
