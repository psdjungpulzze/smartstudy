defmodule FunSheepWeb.ExportControllerTest do
  use FunSheepWeb.ConnCase, async: true

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
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Bio Quiz",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "GET /export/study-guide/:id" do
    test "returns text file download", %{conn: conn, user_role: ur, schedule: schedule} do
      {:ok, guide} =
        FunSheep.Learning.create_study_guide(%{
          content: %{
            "title" => "Test Guide",
            "generated_for" => "Biology",
            "test_date" => "2026-04-25",
            "aggregate_score" => 80,
            "sections" => [
              %{
                "chapter_name" => "Ch1",
                "priority" => "High",
                "score" => 70,
                "review_topics" => ["Topic A"],
                "wrong_questions" => []
              }
            ]
          },
          generated_at: DateTime.utc_now(),
          user_role_id: ur.id,
          test_schedule_id: schedule.id
        })

      conn = auth_conn(conn, ur)
      conn = get(conn, ~p"/export/study-guide/#{guide.id}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "study_guide.txt"
      assert conn.resp_body =~ "# Test Guide"
      assert conn.resp_body =~ "Ch1"
    end
  end

  describe "GET /export/readiness/:schedule_id" do
    test "returns text file when readiness data exists", %{
      conn: conn,
      user_role: ur,
      schedule: schedule,
      chapter: chapter
    } do
      {:ok, _readiness} =
        FunSheep.Assessments.create_readiness_score(%{
          user_role_id: ur.id,
          test_schedule_id: schedule.id,
          chapter_scores: %{chapter.id => 75.0},
          topic_scores: %{},
          aggregate_score: 75.0,
          calculated_at: DateTime.utc_now()
        })

      conn = auth_conn(conn, ur)
      conn = get(conn, ~p"/export/readiness/#{schedule.id}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
      assert conn.resp_body =~ "# Test Readiness Report"
      assert conn.resp_body =~ "Bio Quiz"
    end

    test "still generates a zero-state report when no attempts have been recorded yet",
         %{conn: conn, user_role: ur, schedule: schedule} do
      # `latest_readiness/2` now returns a live-computed struct (never nil
      # when the schedule exists), so the report always renders — even with
      # zero attempts. That's the honest "0% so far" view.
      conn = auth_conn(conn, ur)
      conn = get(conn, ~p"/export/readiness/#{schedule.id}")

      assert conn.status == 200
      assert conn.resp_body =~ "# Test Readiness Report"
      assert conn.resp_body =~ "Bio Quiz"
    end
  end
end
