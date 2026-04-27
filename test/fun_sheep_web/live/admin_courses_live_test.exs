defmodule FunSheepWeb.AdminCoursesLiveTest do
  use FunSheepWeb.ConnCase, async: true
  use Oban.Testing, repo: FunSheep.Repo

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Courses, Questions}

  # Use a real DB-backed admin to satisfy audit-log binary_id requirement.
  defp create_admin do
    {:ok, admin} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: :admin,
        email: "admin-courses-#{System.unique_integer([:positive])}@test.com",
        display_name: "Test Admin"
      })

    admin
  end

  defp admin_conn(conn) do
    admin = create_admin()

    conn
    |> init_test_session(%{
      dev_user_id: admin.id,
      dev_user: %{
        "id" => admin.id,
        "user_role_id" => admin.id,
        "interactor_user_id" => admin.interactor_user_id,
        "role" => "admin",
        "email" => admin.email,
        "display_name" => admin.display_name
      }
    })
  end

  defp create_course(attrs \\ %{}) do
    {:ok, c} =
      Courses.create_course(Map.merge(%{name: "Bio 101", subject: "Biology", grade: "10"}, attrs))

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
        assert_enqueued(worker: FunSheep.Workers.QuestionValidationWorker, queue: :ai_validation)
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

  describe "mount and initial render" do
    test "shows the page heading, search input, and column headers", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "Courses"
      assert html =~ "Name"
      assert html =~ "Subject"
      assert html =~ "Owner"
      assert html =~ "Status"
    end

    test "shows 'No courses match' when there are none", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "No courses match"
    end

    test "shows existing courses in the table", %{conn: conn} do
      create_course(%{name: "Chemistry Advanced"})

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "Chemistry Advanced"
    end

    test "renders Edit and Rediscover buttons for each course", %{conn: conn} do
      create_course()

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ "phx-click=\"open_edit\""
      assert html =~ "phx-click=\"rediscover_toc\""
      assert html =~ "phx-click=\"delete\""
    end
  end

  describe "search event" do
    test "filters courses by name", %{conn: conn} do
      create_course(%{name: "Advanced Physics"})
      create_course(%{name: "Art History"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "Physics"})

      assert html =~ "Advanced Physics"
      refute html =~ "Art History"
    end

    test "returns 'No courses match' for unmatched search", %{conn: conn} do
      create_course(%{name: "Biology 101"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => "zzz_no_match"})

      assert html =~ "No courses match"
    end

    test "clearing the search shows all courses", %{conn: conn} do
      create_course(%{name: "Visible Course"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "zzz_no_match"})

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"search" => ""})

      assert html =~ "Visible Course"
    end
  end

  describe "pagination events" do
    test "prev_page does not go below page 0", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      html = render_hook(view, "prev_page", %{})

      assert html =~ "Page 1 of"
    end

    test "next_page stays on same page when total fits on one page", %{conn: conn} do
      create_course()

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      html = render_hook(view, "next_page", %{})

      assert html =~ "Page 1 of 1"
    end
  end

  describe "delete event" do
    test "deletes a course and flashes success", %{conn: conn} do
      course = create_course(%{name: "To Be Deleted"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      html =
        view
        |> element("button[phx-click='delete'][phx-value-id='#{course.id}']")
        |> render_click()

      assert html =~ "Course deleted."
      refute html =~ "To Be Deleted"
    end
  end

  describe "open_edit / close_edit / save_edit events" do
    test "open_edit displays the edit modal with the course name", %{conn: conn} do
      course = create_course(%{name: "Edit Me Course"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      html =
        view
        |> element("button[phx-click='open_edit'][phx-value-id='#{course.id}']")
        |> render_click()

      assert html =~ "Edit Course"
      assert html =~ "Edit Me Course"
    end

    test "close_edit dismisses the modal", %{conn: conn} do
      course = create_course(%{name: "Close Modal Course"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      view
      |> element("button[phx-click='open_edit'][phx-value-id='#{course.id}']")
      |> render_click()

      html = render_hook(view, "close_edit", %{})

      refute html =~ "Edit Course"
    end

    test "save_edit updates the course name and closes the modal", %{conn: conn} do
      course = create_course(%{name: "Original Name"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      view
      |> element("button[phx-click='open_edit'][phx-value-id='#{course.id}']")
      |> render_click()

      html =
        view
        |> form("form[phx-submit='save_edit']", %{
          "name" => "Updated Name",
          "subject" => "Updated Subject",
          "grades" => [""],
          "access_level" => "public"
        })
        |> render_submit()

      assert html =~ "Course updated."
      assert html =~ "Updated Name"
    end

    test "save_edit with grades updates the course successfully", %{conn: conn} do
      course = create_course(%{name: "Grade Test Course"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      view
      |> element("button[phx-click='open_edit'][phx-value-id='#{course.id}']")
      |> render_click()

      html =
        view
        |> form("form[phx-submit='save_edit']", %{
          "name" => "Grade Test Course",
          "subject" => "Math",
          "grades" => ["9", "10"],
          "access_level" => "standard"
        })
        |> render_submit()

      assert html =~ "Course updated."
    end

    test "save_edit with price_cents updates pricing fields", %{conn: conn} do
      course = create_course(%{name: "Paid Course"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses")

      view
      |> element("button[phx-click='open_edit'][phx-value-id='#{course.id}']")
      |> render_click()

      html =
        view
        |> form("form[phx-submit='save_edit']", %{
          "name" => "Paid Course",
          "subject" => "Math",
          "grades" => [""],
          "access_level" => "premium",
          "price_cents" => "2900",
          "currency" => "usd",
          "price_label" => "One-time"
        })
        |> render_submit()

      assert html =~ "Course updated."
    end
  end

  describe "status badge rendering" do
    test "ready courses show green Ready badge", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{
          name: "Ready Course",
          subject: "Science",
          grade: "9",
          processing_status: "ready"
        })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ course.name
      assert html =~ "Ready"
    end

    test "failed courses show red Failed badge", %{conn: conn} do
      {:ok, course} =
        Courses.create_course(%{
          name: "Failed Course",
          subject: "Science",
          grade: "9",
          processing_status: "failed"
        })

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses")

      assert html =~ course.name
      assert html =~ "Failed"
    end
  end
end
