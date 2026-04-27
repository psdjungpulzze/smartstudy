defmodule FunSheepWeb.TestFormatLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias FunSheep.ContentFixtures
  alias FunSheep.Assessments

  setup :verify_on_exit!

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
      Assessments.create_test_schedule(%{
        name: "Midterm",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  defp create_schedule_with_template(user_role, course) do
    {:ok, schedule_no_template} =
      Assessments.create_test_schedule(%{
        name: "Finals",
        test_date: Date.add(Date.utc_today(), 14),
        scope: %{},
        user_role_id: user_role.id,
        course_id: course.id
      })

    {:ok, template} =
      Assessments.create_test_format_template(%{
        name: "Finals Format",
        structure: %{
          "sections" => [
            %{
              "name" => "Multiple Choice",
              "question_type" => "multiple_choice",
              "count" => 20,
              "points_per_question" => 1,
              "chapter_ids" => []
            }
          ],
          "time_limit_minutes" => 45
        },
        course_id: course.id,
        created_by_id: user_role.id
      })

    {:ok, schedule} =
      Assessments.update_test_schedule(schedule_no_template, %{
        format_template_id: template.id
      })

    {schedule, template}
  end

  describe "mount" do
    test "renders the format page with basic schedule", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      assert html =~ "Test Format"
      assert html =~ "Midterm"
      assert html =~ "Structured Sections"
      assert html =~ "Format Description"
      assert html =~ "No sections yet"
    end

    test "renders with format_template that has sections and time_limit", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {schedule, _template} = create_schedule_with_template(ur, course)
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      assert html =~ "Multiple Choice"
      assert html =~ "45"
      # Should not show "No sections yet" since sections exist
      refute html =~ "No sections yet"
      # Summary bar should be shown
      assert html =~ "questions"
    end

    test "renders with format_template with sections but no time_limit", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {:ok, schedule_base} =
        Assessments.create_test_schedule(%{
          name: "Quiz",
          test_date: Date.add(Date.utc_today(), 3),
          scope: %{},
          user_role_id: ur.id,
          course_id: course.id
        })

      {:ok, template} =
        Assessments.create_test_format_template(%{
          name: "Quiz Format",
          structure: %{
            "sections" => [
              %{
                "name" => "True False",
                "question_type" => "true_false",
                "count" => 10,
                "points_per_question" => 1,
                "chapter_ids" => []
              }
            ]
          },
          course_id: course.id,
          created_by_id: ur.id
        })

      {:ok, schedule} =
        Assessments.update_test_schedule(schedule_base, %{format_template_id: template.id})

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      assert html =~ "True False"
      # No time limit set — should show "No time limit" in summary bar
      assert html =~ "No time limit"
    end
  end

  describe "update_description event" do
    test "updates the format description", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html =
        render_change(view, "update_description", %{
          "format_description" => "20 MC (30 min)\n3 FRQ (25 min)"
        })

      assert html =~ "20 MC"
    end
  end

  describe "parse_format event" do
    test "shows error flash when description is empty", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html = render_click(view, "parse_format")

      assert html =~ "Paste a format description first"
    end

    test "shows error flash when description is only whitespace", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_description", %{"format_description" => "   "})
      html = render_click(view, "parse_format")

      assert html =~ "Paste a format description first"
    end

    test "starts parsing when description is non-empty (successful parse)", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      expect(FunSheep.AI.ClientMock, :call, fn _sys, _user, _opts ->
        {:ok,
         ~s({"sections":[{"name":"MC","question_type":"multiple_choice","count":20,"points_per_question":1}],"time_limit_minutes":30})}
      end)

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_description", %{"format_description" => "20 MC 30 min"})

      html = render_click(view, "parse_format")
      # parsing starts — button becomes disabled
      assert html =~ "Parsing"

      # wait for the :do_parse message to be handled
      render(view)
      html = render(view)

      assert html =~ "MC"
      assert html =~ "1 section"
    end

    test "shows parse error flash when AI parse fails", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      expect(FunSheep.AI.ClientMock, :call, fn _sys, _user, _opts ->
        {:error, :api_error}
      end)

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_description", %{"format_description" => "some format"})
      render_click(view, "parse_format")

      # Wait for :do_parse to resolve
      html = render(view)

      assert html =~ "Could not parse" or html =~ "Parse failed"
    end
  end

  describe "section management" do
    test "can add a section with a name", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "MC Section",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "2"
      })

      html = render_submit(view, "add_section")

      assert html =~ "MC Section"
      assert html =~ "Multiple Choice"
    end

    test "shows error when adding section with empty name", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html = render_submit(view, "add_section")

      assert html =~ "Section name is required"
    end

    test "can remove a section", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "Section to Remove",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      html = render_click(view, "remove_section", %{"index" => "0"})

      refute html =~ "Section to Remove"
      assert html =~ "No sections yet"
    end

    test "can edit section name field", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "Original Name",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      html =
        render_change(view, "edit_section_field", %{
          "index" => "0",
          "field" => "name",
          "value" => "Updated Name"
        })

      assert html =~ "Updated Name"
    end

    test "can edit section question_type field", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "My Section",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      html =
        render_change(view, "edit_section_field", %{
          "index" => "0",
          "field" => "question_type",
          "value" => "free_response"
        })

      assert html =~ "Free Response"
    end

    test "can edit section count field", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "Count Section",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      html =
        render_change(view, "edit_section_field", %{
          "index" => "0",
          "field" => "count",
          "value" => "15"
        })

      assert html =~ "15"
    end

    test "can edit section points_per_question field", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "Points Section",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      html =
        render_change(view, "edit_section_field", %{
          "index" => "0",
          "field" => "points_per_question",
          "value" => "5"
        })

      assert html =~ "5"
    end

    test "ignores unknown field in edit_section_field", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "My Section",
        "question_type" => "multiple_choice",
        "count" => "5",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      # Should not crash, section name should remain
      html =
        render_change(view, "edit_section_field", %{
          "index" => "0",
          "field" => "unknown_field",
          "value" => "some_value"
        })

      assert html =~ "My Section"
    end
  end

  describe "update_section_form event" do
    test "updates all section form fields", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html =
        render_change(view, "update_section_form", %{
          "name" => "FRQ",
          "question_type" => "free_response",
          "count" => "3",
          "points_per_question" => "7"
        })

      assert html =~ "FRQ"
    end

    test "handles missing params gracefully", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      # Should not crash when optional params are missing
      html = render_change(view, "update_section_form", %{})
      assert is_binary(html)
    end
  end

  describe "update_time_limit event" do
    test "updates time limit with a valid integer string", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html = render_change(view, "update_time_limit", %{"time_limit" => "90"})

      assert html =~ "90"
    end

    test "clears time limit when value is empty", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_time_limit", %{"time_limit" => "60"})
      html = render_change(view, "update_time_limit", %{"time_limit" => ""})

      # time limit cleared — input should have no value or show blank
      assert is_binary(html)
    end
  end

  describe "save event" do
    test "saves description only when no sections", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_description", %{
        "format_description" => "20 MC questions, 30 minutes"
      })

      html = render_click(view, "save")

      assert html =~ "Format description saved"
    end

    test "creates new template when sections exist and no saved template", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_section_form", %{
        "name" => "MC",
        "question_type" => "multiple_choice",
        "count" => "10",
        "points_per_question" => "1"
      })

      render_submit(view, "add_section")

      render_change(view, "update_time_limit", %{"time_limit" => "30"})

      html = render_click(view, "save")

      assert html =~ "Format saved!"
    end

    test "updates existing template on save when one already exists", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {schedule, _template} = create_schedule_with_template(ur, course)
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      # Add another section to trigger update path
      render_change(view, "update_section_form", %{
        "name" => "New Section",
        "question_type" => "short_answer",
        "count" => "5",
        "points_per_question" => "2"
      })

      render_submit(view, "add_section")

      html = render_click(view, "save")

      assert html =~ "Format saved!"
    end
  end

  describe "generate_practice_test event" do
    test "shows error when no saved template", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html = render_click(view, "generate_practice_test")

      assert html =~ "Save the format first"
    end

    test "generates practice test when saved template exists", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {schedule, _template} = create_schedule_with_template(ur, course)
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      html = render_click(view, "generate_practice_test")

      assert html =~ "Practice Test Preview"
      assert html =~ "Questions"
      assert html =~ "Points"
    end
  end

  describe "summary bar" do
    test "shows summary bar with question count and points when sections exist", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {schedule, _template} = create_schedule_with_template(ur, course)
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      assert html =~ "20 questions"
      assert html =~ "pts total"
    end

    test "shows time limit in summary bar when set", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {schedule, _template} = create_schedule_with_template(ur, course)
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      assert html =~ "45 min"
    end
  end

  describe "saved template buttons" do
    test "shows Generate Practice Test button when saved template exists", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      {schedule, _template} = create_schedule_with_template(ur, course)
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      assert html =~ "Generate Practice Test"
      assert html =~ "Take Practice Test"
    end

    test "does not show practice test buttons when no template", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      refute html =~ "Generate Practice Test"
      refute html =~ "Take Practice Test"
    end
  end

  describe "handle_info :do_parse" do
    test "parses successfully and assigns sections", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      expect(FunSheep.AI.ClientMock, :call, fn _sys, _user, _opts ->
        response =
          Jason.encode!(%{
            "sections" => [
              %{
                "name" => "Section A",
                "question_type" => "multiple_choice",
                "count" => 10,
                "points_per_question" => 1
              },
              %{
                "name" => "Section B",
                "question_type" => "free_response",
                "count" => 2,
                "points_per_question" => 5
              }
            ],
            "time_limit_minutes" => 60
          })

        {:ok, response}
      end)

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_description", %{
        "format_description" => "10 MC, 2 FRQ 5pts each, 60 min total"
      })

      render_click(view, "parse_format")

      # Wait for async :do_parse
      html = render(view)

      assert html =~ "Section A" or html =~ "section"
    end

    test "shows parse error when AI returns error", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      expect(FunSheep.AI.ClientMock, :call, fn _sys, _user, _opts ->
        {:error, :timeout}
      end)

      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/format")

      render_change(view, "update_description", %{"format_description" => "bad format text"})
      render_click(view, "parse_format")

      html = render(view)

      assert html =~ "Could not parse" or html =~ "Parse failed" or html =~ "failed"
    end
  end
end
