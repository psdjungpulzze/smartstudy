defmodule FunSheepWeb.AdminQuestionReviewLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Courses, Questions}

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "test_admin",
      dev_user: %{
        "id" => "test_admin",
        "role" => "admin",
        "email" => "admin@test.com",
        "display_name" => "Test Admin",
        "user_role_id" => "test_admin"
      }
    })
  end

  defp seed_queue do
    {:ok, course} =
      Courses.create_course(%{name: "Biology 101", subject: "Biology", grade: "10"})

    {:ok, q} =
      Questions.create_question(%{
        content: "What is a cell's powerhouse?",
        answer: "Mitochondria",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        validation_status: :needs_review,
        validation_score: 72.0,
        validation_report: %{
          "topic_relevance_score" => 72,
          "topic_relevance_reason" => "Relevant to biology but slightly broad.",
          "completeness" => %{"passed" => true, "issues" => []},
          "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
          "explanation" => %{
            "valid" => false,
            "suggested_explanation" => "Mitochondria produce ATP, the cell's energy currency."
          },
          "verdict" => "needs_fix"
        }
      })

    {course, q}
  end

  describe "render" do
    test "shows empty state when no questions need review", %{conn: conn} do
      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "Queue is empty"
      assert html =~ "Question Review Queue"
    end

    test "lists questions in the review queue", %{conn: conn} do
      {_course, _q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      assert html =~ "What is a cell&#39;s powerhouse?"
      assert html =~ "Biology 101"
      assert html =~ "72"
      assert html =~ "Relevant to biology"
    end

    test "shows queue count", %{conn: conn} do
      seed_queue()
      seed_queue()

      conn = admin_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/admin/questions/review")

      # count pill shows 2
      assert html =~ ~s(<span class="text-2xl font-bold text-[#4CD964]">2</span>)
    end
  end

  describe "approve event" do
    test "flips the question to passed and removes it from the queue", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "approve", %{"id" => q.id})

      assert html =~ "Queue is empty"
      assert Questions.get_question!(q.id).validation_status == :passed
    end
  end

  describe "reject event" do
    test "flips the question to failed and removes it from the queue", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "reject", %{"id" => q.id})

      assert html =~ "Queue is empty"
      assert Questions.get_question!(q.id).validation_status == :failed
    end
  end

  describe "edit flow" do
    test "edit event shows an editable form", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      html = render_click(view, "edit", %{"id" => q.id})

      assert html =~ "Save &amp; Approve"
      assert html =~ "Cancel"
      assert html =~ "What is a cell&#39;s powerhouse?"
    end

    test "save_edit updates the question and approves it", %{conn: conn} do
      {_course, q} = seed_queue()

      conn = admin_conn(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/questions/review")

      _ = render_click(view, "edit", %{"id" => q.id})

      render_submit(view, "save_edit", %{
        "id" => q.id,
        "question" => %{
          "content" => "What produces ATP in eukaryotic cells?",
          "answer" => "Mitochondria",
          "explanation" => "Mitochondria use oxidative phosphorylation to make ATP."
        }
      })

      updated = Questions.get_question!(q.id)
      assert updated.content == "What produces ATP in eukaryotic cells?"
      assert updated.explanation == "Mitochondria use oxidative phosphorylation to make ATP."
      assert updated.validation_status == :passed
    end
  end
end
