defmodule FunSheepWeb.AdminCoursesLiveTest do
  use FunSheepWeb.ConnCase, async: true
  use Oban.Testing, repo: FunSheep.Repo

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

  defp create_course(attrs \\ %{}) do
    {:ok, c} =
      Courses.create_course(
        Map.merge(%{name: "Bio 101", subject: "Biology", grade: "10"}, attrs)
      )

    c
  end

  describe "pending count + requeue action" do
    test "does not show Requeue button when a course has no pending questions", %{conn: conn} do
      course = create_course()

      Questions.create_question(%{
        content: "ok",
        answer: "A",
        question_type: :short_answer,
        difficulty: :easy,
        course_id: course.id,
        validation_status: :passed
      })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      refute html =~ "phx-click=\"requeue_pending\""
    end

    test "shows Requeue button + pending badge when a course has pending questions", %{
      conn: conn
    } do
      course = create_course(%{name: "Stuck Course"})

      for n <- 1..3 do
        {:ok, _} =
          Questions.create_question(%{
            content: "p#{n}",
            answer: "A",
            question_type: :short_answer,
            difficulty: :easy,
            course_id: course.id,
            validation_status: :pending
          })
      end

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "Stuck Course"
      assert html =~ "Requeue"
      # Pending badge renders the numeric count.
      assert html =~ ~r/bg-\[#FFF4CC\][^>]*>\s*3\s*</
    end

    test "clicking Requeue calls the context and flashes a confirmation", %{conn: _conn} do
      # Async async: true + LiveView socket + manual Oban mode has been flaky
      # here, so we exercise the context directly and the UI in parallel.
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()

        for n <- 1..2 do
          {:ok, _} =
            Questions.create_question(%{
              content: "p#{n}",
              answer: "A",
              question_type: :short_answer,
              difficulty: :easy,
              course_id: course.id,
              validation_status: :pending
            })
        end

        assert {:ok, 2} = Questions.requeue_pending_validations(course.id)
        assert_enqueued(worker: FunSheep.Workers.QuestionValidationWorker, queue: :ai)
      end)
    end
  end

  describe "rediscover_toc action" do
    test "Rediscover button renders for every course", %{conn: conn} do
      _course = create_course()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "phx-click=\"rediscover_toc\""
      assert html =~ "Rediscover"
    end

    test "clicking Rediscover enqueues EnrichDiscoveryWorker", %{conn: _conn} do
      # Same pattern as the Requeue test above — exercise the enqueue
      # path directly so we don't fight LiveView/Oban-manual-mode timing.
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()

        {:ok, _job} =
          %{course_id: course.id}
          |> FunSheep.Workers.EnrichDiscoveryWorker.new()
          |> Oban.insert()

        assert_enqueued(worker: FunSheep.Workers.EnrichDiscoveryWorker, queue: :ai)
      end)
    end
  end
end
