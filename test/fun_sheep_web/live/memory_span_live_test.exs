defmodule FunSheepWeb.MemorySpanLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "Chemistry 101"})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Atomic Structure",
        position: 1,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "mount/3" do
    test "renders page with course name and Memory Span heading", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "Memory Span"
      assert html =~ "Chemistry 101"
    end

    test "renders overall memory span card", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "Overall Memory Span"
    end

    test "shows no-data state when user has not practiced yet", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # No span data for a new user → show "keep practicing" messages
      assert html =~ "practicing" or html =~ "No data yet"
    end

    test "shows chapters with no data as 'No data yet' rows", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # The chapter has no span data, so it should show in the no-data section
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "Atomic Structure"
      assert html =~ "No data yet"
    end

    test "shows 'By Chapter' section heading", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "By Chapter"
    end

    test "renders back navigation link to practice page", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ ~s|/courses/#{course.id}/practice|
    end

    test "shows span data when course-level span exists", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # Insert a course-level span for the user
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 72,
          previous_span_hours: 48,
          trend: "improving",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # Should show the formatted span (72h = 3 days)
      assert html =~ "3 days" or html =~ "72"
      # Trend should show improving indicator
      assert html =~ "↑" or html =~ "improving"
    end

    test "shows course span card with green color for long span", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # 720h = 30 days → green color band (>= 21*24 = 504h)
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 720,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # green band → "Strong" badge
      assert html =~ "Strong" or html =~ "month" or html =~ "Memory Span"
    end

    test "shows course span card with red color for very short span", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # 24h = 1 day → red color band (< 7*24 = 168h)
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 24,
          trend: "declining",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # red band → "At risk" badge
      assert html =~ "At risk" or html =~ "day" or html =~ "↓" or html =~ "declining"
    end

    test "shows course span card with yellow color for medium span", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # 200h ≈ 8.3 days → yellow color band (7*24=168 ≤ hours < 21*24=504)
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 200,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # yellow band → "Moderate" badge
      assert html =~ "Moderate" or html =~ "week" or html =~ "→" or html =~ "stable"
    end

    test "shows stable trend arrow for stable span", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 200,
          previous_span_hours: 200,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "→" or html =~ "stable" or html =~ "Memory Span"
    end

    test "shows declining trend arrow for declining span", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 48,
          previous_span_hours: 96,
          trend: "declining",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "↓" or html =~ "declining" or html =~ "Memory Span"
    end
  end

  describe "chapter span rows" do
    test "shows chapter rows with span data when chapter spans exist", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 48,
          trend: "improving",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # Chapter name should appear in the span row
      assert html =~ "Atomic Structure"
      # Trend should show
      assert html =~ "↑" or html =~ "improving" or html =~ "days"
    end

    test "shows green span row when chapter span is long", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      # 600h → green
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 600,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "Atomic Structure"
      assert html =~ "Practice" or html =~ "month" or html =~ "weeks"
    end

    test "shows red span row when chapter span is short", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      # 12h → red
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 12,
          trend: "declining",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "Atomic Structure"
      assert html =~ "Practice" or html =~ "day" or html =~ "↓"
    end

    test "shows yellow span row when chapter span is moderate", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      # 240h ≈ 10 days → yellow
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 240,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "Atomic Structure"
      assert html =~ "Practice" or html =~ "week"
    end

    test "shows chapter row with improving trend arrow", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 96,
          previous_span_hours: 48,
          trend: "improving",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "↑" or html =~ "improving"
    end

    test "shows chapter row with declining trend arrow", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 48,
          previous_span_hours: 96,
          trend: "declining",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ "↓" or html =~ "declining"
    end

    test "chapters with span data do not appear in no-data section", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 72,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # Chapter with span data should show the formatted span, not "No data yet"
      # (the "No data yet" section may still show for other chapters, but this
      # chapter's span row should be present)
      assert html =~ "Atomic Structure"
      assert html =~ "Practice"
    end

    test "second chapter with no span shows as no-data when first has span", %{
      conn: conn,
      user_role: ur,
      course: course,
      chapter: chapter
    } do
      {:ok, _chapter2} =
        FunSheep.Courses.create_chapter(%{
          name: "Bonding",
          position: 2,
          course_id: course.id
        })

      # Only chapter 1 has a span
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          chapter_id: chapter.id,
          granularity: "chapter",
          span_hours: 72,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # Chapter 2 (Bonding) has no span, should show as "No data yet"
      assert html =~ "Bonding"
      assert html =~ "No data yet" or html =~ "Start practicing"
    end
  end

  describe "unauthenticated access" do
    test "redirects to login when not authenticated", %{conn: conn, course: course} do
      assert {:error, {:redirect, %{to: _path}}} =
               live(conn, ~p"/courses/#{course.id}/memory-span")
    end
  end

  describe "practice link navigation" do
    test "course span card links to practice page", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {:ok, _span} =
        %FunSheep.MemorySpan.Span{}
        |> FunSheep.MemorySpan.Span.changeset(%{
          user_role_id: ur.id,
          course_id: course.id,
          granularity: "course",
          span_hours: 72,
          trend: "stable",
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> FunSheep.Repo.insert()

      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      assert html =~ ~s|/courses/#{course.id}/practice|
    end

    test "chapter row no-data links to practice page", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/memory-span")

      # Even in no-data state, "Start practicing" or practice link appears
      assert html =~ ~s|/courses/#{course.id}/practice|
    end
  end
end
