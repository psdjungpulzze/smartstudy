defmodule StudySmartWeb.ExportController do
  use StudySmartWeb, :controller

  alias StudySmart.{Export, Learning, Assessments, Courses}

  def study_guide(conn, %{"id" => id}) do
    guide = Learning.get_study_guide!(id)
    text = Export.export_study_guide_text(guide)

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("content-disposition", "attachment; filename=\"study_guide.txt\"")
    |> send_resp(200, text)
  end

  def readiness_report(conn, %{"schedule_id" => schedule_id}) do
    user = get_session(conn, :dev_user)

    if user do
      schedule = Assessments.get_test_schedule_with_course!(schedule_id)
      readiness = Assessments.latest_readiness(user["user_role_id"], schedule_id)

      if readiness do
        course = Courses.get_course_with_chapters!(schedule.course_id)
        text = Export.export_readiness_report_text(schedule, readiness, course.chapters)

        conn
        |> put_resp_content_type("text/plain")
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"readiness_report.txt\""
        )
        |> send_resp(200, text)
      else
        conn
        |> put_flash(:error, "No readiness data available yet")
        |> redirect(to: ~p"/tests/#{schedule_id}/assess")
      end
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/dev/login")
    end
  end
end
