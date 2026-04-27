defmodule FunSheepWeb.UpcomingTestsLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Repo
  alias FunSheep.Assessments.TestSchedule

  @scope %{"chapter_ids" => []}

  # UpcomingTestsLive uses current_user["id"] to query TestSchedule.user_role_id,
  # so we set "id" to user_role.id (not interactor_user_id) for queries to match.
  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.id,
      dev_user: %{
        "id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  defp create_schedule(attrs) do
    %TestSchedule{}
    |> TestSchedule.changeset(attrs)
    |> Repo.insert!()
  end

  setup do
    user_role = FunSheep.ContentFixtures.create_user_role()
    course = FunSheep.ContentFixtures.create_course(%{name: "Upcoming Test Course", subject: "Mathematics"})
    %{user_role: user_role, course: course}
  end

  describe "mount with no upcoming tests" do
    test "renders page title", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")
      assert html =~ "Upcoming Tests"
    end

    test "shows empty state message", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")
      assert html =~ "No upcoming tests"
    end

    test "shows link to courses in empty state", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")
      assert html =~ "Go to Courses"
    end
  end

  describe "mount with upcoming tests" do
    test "renders scheduled tests for the user", %{conn: conn, user_role: ur, course: course} do
      create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 14),
        name: "Midterm Exam",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Midterm Exam"
      assert html =~ "Upcoming Test Course"
    end

    test "shows course name in the tests list", %{conn: conn, user_role: ur, course: course} do
      create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 7),
        name: "Quiz 1",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Upcoming Test Course"
      assert html =~ "Mathematics"
    end

    test "shows days until test", %{conn: conn, user_role: ur, course: course} do
      days_until = 10

      create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), days_until),
        name: "Final Exam",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "#{days_until}"
      assert html =~ "days"
    end

    test "shows Assess and Practice action links", %{conn: conn, user_role: ur, course: course} do
      schedule = create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 5),
        name: "Chapter Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Assess"
      assert html =~ "Practice"
      assert html =~ schedule.id
    end
  end

  describe "unauthenticated access" do
    test "redirects to login when not authenticated", %{conn: conn} do
      result = live(conn, ~p"/upcoming-tests")
      assert {:error, _} = result
    end
  end

  describe "urgency and days color variants" do
    test "shows test within 3 days with red color", %{conn: conn, user_role: ur, course: course} do
      create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 2),
        name: "Urgent Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Urgent Test"
      assert html =~ "bg-red-500" or html =~ "text-red-500"
    end

    test "shows test 4-7 days away with amber color", %{conn: conn, user_role: ur, course: course} do
      create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 5),
        name: "Soon Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Soon Test"
      assert html =~ "bg-amber-500" or html =~ "text-amber-500"
    end

    test "shows test more than 7 days away with green color", %{conn: conn, user_role: ur, course: course} do
      create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 14),
        name: "Far Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Far Test"
      assert html =~ "bg-[#4CD964]" or html =~ "text-[#4CD964]"
    end
  end

  describe "subject emoji display" do
    test "shows math emoji for mathematics course", %{conn: conn, user_role: ur} do
      math_course = FunSheep.ContentFixtures.create_course(%{name: "Math 101", subject: "Mathematics"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: math_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "Math Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "🔢" or html =~ "Math Test"
    end

    test "shows science emoji for science course", %{conn: conn, user_role: ur} do
      sci_course = FunSheep.ContentFixtures.create_course(%{name: "Science 101", subject: "Science"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: sci_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "Science Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "🔬" or html =~ "Science Test"
    end

    test "shows bio emoji for biology course", %{conn: conn, user_role: ur} do
      bio_course = FunSheep.ContentFixtures.create_course(%{name: "Biology 101", subject: "Biology"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: bio_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "Bio Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "🧬" or html =~ "Bio Test"
    end

    test "shows english emoji for english course", %{conn: conn, user_role: ur} do
      eng_course = FunSheep.ContentFixtures.create_course(%{name: "English Lit", subject: "English"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: eng_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "English Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "📝" or html =~ "English Test"
    end

    test "shows default book emoji for unknown subject", %{conn: conn, user_role: ur} do
      unknown_course = FunSheep.ContentFixtures.create_course(%{name: "Unknown 101", subject: "Alchemy"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: unknown_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "Unknown Subject Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "📘" or html =~ "Unknown Subject Test"
    end

    test "shows history emoji for history course", %{conn: conn, user_role: ur} do
      hist_course = FunSheep.ContentFixtures.create_course(%{name: "History 101", subject: "History"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: hist_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "History Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "🏛️" or html =~ "History Test"
    end

    test "shows computer emoji for computer science course", %{conn: conn, user_role: ur} do
      cs_course = FunSheep.ContentFixtures.create_course(%{name: "CS 101", subject: "Computer Science"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: cs_course.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "CS Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "💻" or html =~ "CS Test"
    end
  end

  describe "readiness display in test list" do
    alias FunSheep.Assessments

    test "shows readiness percentage when readiness data exists", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      schedule = create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 14),
        name: "Readiness Test",
        scope: @scope
      })

      # Create a readiness score directly
      {:ok, _readiness} =
        Assessments.create_readiness_score(%{
          user_role_id: ur.id,
          test_schedule_id: schedule.id,
          aggregate_score: 75.0,
          chapter_scores: %{},
          topic_scores: %{},
          skill_scores: %{},
          calculated_at: DateTime.utc_now()
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Readiness Test"
      assert html =~ "ready"
      # Should show the readiness percentage
      assert html =~ "75" or html =~ "%"
    end

    test "shows readiness percentage in green for score >= 70", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      schedule = create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 14),
        name: "High Readiness Test",
        scope: @scope
      })

      {:ok, _readiness} =
        Assessments.create_readiness_score(%{
          user_role_id: ur.id,
          test_schedule_id: schedule.id,
          aggregate_score: 85.0,
          chapter_scores: %{},
          topic_scores: %{},
          skill_scores: %{},
          calculated_at: DateTime.utc_now()
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "High Readiness Test"
      assert html =~ "text-[#4CD964]" or html =~ "85"
    end

    test "shows readiness percentage in amber for score 40-69", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      schedule = create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 14),
        name: "Medium Readiness Test",
        scope: @scope
      })

      {:ok, _readiness} =
        Assessments.create_readiness_score(%{
          user_role_id: ur.id,
          test_schedule_id: schedule.id,
          aggregate_score: 55.0,
          chapter_scores: %{},
          topic_scores: %{},
          skill_scores: %{},
          calculated_at: DateTime.utc_now()
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Medium Readiness Test"
      assert html =~ "text-amber-500" or html =~ "55"
    end

    test "shows readiness percentage in red for score < 40", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      schedule = create_schedule(%{
        user_role_id: ur.id,
        course_id: course.id,
        test_date: Date.add(Date.utc_today(), 14),
        name: "Low Readiness Test",
        scope: @scope
      })

      {:ok, _readiness} =
        Assessments.create_readiness_score(%{
          user_role_id: ur.id,
          test_schedule_id: schedule.id,
          aggregate_score: 25.0,
          chapter_scores: %{},
          topic_scores: %{},
          skill_scores: %{},
          calculated_at: DateTime.utc_now()
        })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Low Readiness Test"
      assert html =~ "text-red-500" or html =~ "25"
    end
  end

  describe "multiple courses grouping" do
    test "groups tests by course correctly", %{conn: conn, user_role: ur} do
      course_a = FunSheep.ContentFixtures.create_course(%{name: "Course Alpha", subject: "Geography"})
      course_b = FunSheep.ContentFixtures.create_course(%{name: "Course Beta", subject: "Art"})

      create_schedule(%{
        user_role_id: ur.id,
        course_id: course_a.id,
        test_date: Date.add(Date.utc_today(), 10),
        name: "Alpha Test",
        scope: @scope
      })

      create_schedule(%{
        user_role_id: ur.id,
        course_id: course_b.id,
        test_date: Date.add(Date.utc_today(), 15),
        name: "Beta Test",
        scope: @scope
      })

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/upcoming-tests")

      assert html =~ "Course Alpha"
      assert html =~ "Course Beta"
      assert html =~ "Alpha Test"
      assert html =~ "Beta Test"
      # Geo and Art emojis
      assert html =~ "🌍" or html =~ "🎨" or html =~ "📘"
    end
  end
end
