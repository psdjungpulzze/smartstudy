defmodule FunSheep.QuestionsFiguresTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.{Content, ContentFixtures, Questions, Repo}
  alias FunSheep.Questions.Question

  defp create_course do
    {:ok, course} =
      FunSheep.Courses.create_course(%{name: "Bio", subject: "Biology", grade: "10"})

    course
  end

  defp create_figure(material, page) do
    {:ok, figure} =
      Content.create_source_figure(%{
        ocr_page_id: page.id,
        material_id: material.id,
        page_number: 1,
        figure_type: :table,
        caption: "Table 2.1",
        image_path: "figures/test.png"
      })

    figure
  end

  describe "attach_figures/2" do
    setup do
      course = create_course()
      material = ContentFixtures.create_uploaded_material(%{course: course})

      {:ok, page} =
        Content.create_ocr_page(%{material_id: material.id, page_number: 1, status: :completed})

      figure = create_figure(material, page)

      {:ok, question} =
        Questions.create_question(%{
          validation_status: :passed,
          content: "Q",
          answer: "A",
          question_type: :short_answer,
          difficulty: :easy,
          course_id: course.id
        })

      %{question: question, figure: figure}
    end

    test "attaches a figure", %{question: question, figure: figure} do
      assert {:ok, 1} = Questions.attach_figures(question, [figure.id])
      loaded = question |> Repo.preload(:figures)
      assert [%{id: fid}] = loaded.figures
      assert fid == figure.id
    end

    test "is idempotent on duplicate attach", %{question: question, figure: figure} do
      {:ok, 1} = Questions.attach_figures(question, [figure.id])
      {:ok, 0} = Questions.attach_figures(question, [figure.id])
      loaded = question |> Repo.preload(:figures)
      assert length(loaded.figures) == 1
    end

    test "no-ops on empty list", %{question: question} do
      assert {:ok, 0} = Questions.attach_figures(question, [])
    end

    test "with_figures preloads", %{question: question, figure: figure} do
      {:ok, _} = Questions.attach_figures(question, [figure.id])
      preloaded = Questions.with_figures(Repo.get!(Question, question.id))
      assert [%{id: _}] = preloaded.figures
    end
  end
end
