defmodule FunSheep.Questions.QuestionGroupTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Questions.QuestionGroup

  # ── Fixtures ─────────────────────────────────────────────────────────────

  defp make_course do
    {:ok, course} = Courses.create_course(%{name: "Biology 101", subject: "Biology", grade: "10"})
    course
  end

  defp valid_group_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        stimulus_type: :reading_passage,
        stimulus_content:
          String.duplicate("word ", 15) <>
            "This is a long enough passage to pass the minimum length validation."
      },
      overrides
    )
  end

  # ── Changeset ─────────────────────────────────────────────────────────────

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = QuestionGroup.changeset(%QuestionGroup{}, valid_group_attrs())
      assert changeset.valid?
    end

    test "requires stimulus_type" do
      changeset =
        QuestionGroup.changeset(%QuestionGroup{}, valid_group_attrs(%{stimulus_type: nil}))

      assert %{stimulus_type: [_ | _]} = errors_on(changeset)
    end

    test "requires stimulus_content" do
      changeset =
        QuestionGroup.changeset(%QuestionGroup{}, valid_group_attrs(%{stimulus_content: nil}))

      assert %{stimulus_content: [_ | _]} = errors_on(changeset)
    end

    test "rejects stimulus_content shorter than 50 characters" do
      changeset =
        QuestionGroup.changeset(%QuestionGroup{}, valid_group_attrs(%{stimulus_content: "short"}))

      assert %{stimulus_content: [_ | _]} = errors_on(changeset)
    end

    test "auto-computes word_count from stimulus_content" do
      content = "one two three four five"

      changeset =
        QuestionGroup.changeset(
          %QuestionGroup{},
          valid_group_attrs(%{stimulus_content: content <> String.duplicate(" pad", 15)})
        )

      # word_count is set from actual content change
      assert Ecto.Changeset.get_change(changeset, :word_count) != nil
    end

    test "word_count equals number of words in stimulus_content" do
      content = Enum.map_join(1..20, " ", fn i -> "word#{i}" end)

      changeset =
        QuestionGroup.changeset(%QuestionGroup{}, %{
          stimulus_type: :reading_passage,
          stimulus_content: content
        })

      assert Ecto.Changeset.get_change(changeset, :word_count) == 20
    end
  end

  # ── Context functions ─────────────────────────────────────────────────────

  describe "create_question_group/1" do
    test "inserts a valid group" do
      course = make_course()
      attrs = valid_group_attrs(%{course_id: course.id})
      assert {:ok, %QuestionGroup{} = group} = Questions.create_question_group(attrs)
      assert group.stimulus_type == :reading_passage
      assert group.course_id == course.id
      assert is_integer(group.word_count)
    end

    test "returns error changeset for missing required fields" do
      assert {:error, changeset} = Questions.create_question_group(%{})
      refute changeset.valid?
    end
  end

  describe "get_question_group/1" do
    test "returns the group for a valid id" do
      {:ok, group} = Questions.create_question_group(valid_group_attrs())
      assert %QuestionGroup{} = Questions.get_question_group(group.id)
    end

    test "returns nil for unknown id" do
      assert nil == Questions.get_question_group(Ecto.UUID.generate())
    end
  end

  describe "get_question_group!/1" do
    test "returns the group for a valid id" do
      {:ok, group} = Questions.create_question_group(valid_group_attrs())
      assert %QuestionGroup{} = Questions.get_question_group!(group.id)
    end

    test "raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Questions.get_question_group!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_group_questions/1" do
    test "returns questions ordered by group_sequence" do
      course = make_course()
      {:ok, group} = Questions.create_question_group(valid_group_attrs(%{course_id: course.id}))

      {:ok, q3} =
        Questions.create_question(%{
          content: "Third?",
          answer: "C",
          question_type: :multiple_choice,
          difficulty: :medium,
          course_id: course.id,
          question_group_id: group.id,
          group_sequence: 3
        })

      {:ok, q1} =
        Questions.create_question(%{
          content: "First?",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :medium,
          course_id: course.id,
          question_group_id: group.id,
          group_sequence: 1
        })

      {:ok, q2} =
        Questions.create_question(%{
          content: "Second?",
          answer: "B",
          question_type: :multiple_choice,
          difficulty: :medium,
          course_id: course.id,
          question_group_id: group.id,
          group_sequence: 2
        })

      result = Questions.list_group_questions(group.id)
      assert Enum.map(result, & &1.id) == [q1.id, q2.id, q3.id]
    end

    test "returns empty list when group has no questions" do
      {:ok, group} = Questions.create_question_group(valid_group_attrs())
      assert [] == Questions.list_group_questions(group.id)
    end
  end
end
