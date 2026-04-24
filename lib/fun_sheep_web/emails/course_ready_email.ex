defmodule FunSheepWeb.Emails.CourseReadyEmail do
  @moduledoc """
  Sent to the course creator when processing finishes and questions are ready.
  """

  import Swoosh.Email

  @from_name "FunSheep"
  @from_email "noreply@funsheep.com"

  def build(to_email, to_name, course_name, course_url) do
    new()
    |> to({to_name || to_email, to_email})
    |> from({@from_name, @from_email})
    |> subject("Your course is ready — #{course_name}")
    |> text_body(text_body(to_name, course_name, course_url))
    |> html_body(html_body(to_name, course_name, course_url))
  end

  defp text_body(name, course_name, course_url) do
    greeting = if name && name != "", do: "Hi #{name},\n\n", else: "Hi,\n\n"

    """
    #{greeting}Your course #{course_name} has finished processing and is ready to use!

    Practice questions have been generated and validated. Start studying now:
    #{course_url}

    — The FunSheep team
    """
  end

  defp html_body(name, course_name, course_url) do
    safe_name =
      if name && name != "",
        do: "Hi #{Phoenix.HTML.html_escape(name) |> Phoenix.HTML.safe_to_string()},",
        else: "Hi,"

    safe_course = Phoenix.HTML.html_escape(course_name) |> Phoenix.HTML.safe_to_string()

    """
    <!DOCTYPE html>
    <html>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #1C1C1E; background: #F5F5F7; margin: 0; padding: 24px;">
        <div style="max-width: 560px; margin: 0 auto; background: #FFFFFF; border-radius: 16px; padding: 32px; box-shadow: 0 2px 8px rgba(0,0,0,0.04);">
          <div style="text-align: center; margin-bottom: 24px;">
            <span style="font-size: 48px;">🐑</span>
          </div>
          <h1 style="font-size: 20px; font-weight: 600; margin: 0 0 8px;">
            Your course is ready!
          </h1>
          <p style="font-size: 16px; line-height: 1.5; margin: 0 0 16px; color: #8E8E93;">
            #{safe_name}
          </p>
          <p style="font-size: 16px; line-height: 1.5; margin: 0 0 24px;">
            <strong>#{safe_course}</strong> has finished processing. Practice questions
            have been generated and are ready for you to study.
          </p>
          <p style="text-align: center; margin: 0 0 24px;">
            <a href="#{course_url}" style="background: #4CD964; color: #FFFFFF; font-weight: 600; text-decoration: none; padding: 14px 32px; border-radius: 9999px; display: inline-block; font-size: 16px;">
              Start studying →
            </a>
          </p>
          <p style="font-size: 12px; color: #8E8E93; line-height: 1.5; margin: 0;">
            Or paste this link into your browser:<br/>
            <a href="#{course_url}" style="color: #007AFF;">#{course_url}</a>
          </p>
        </div>
      </body>
    </html>
    """
  end
end
