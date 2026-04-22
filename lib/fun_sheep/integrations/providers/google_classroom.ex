defmodule FunSheep.Integrations.Providers.GoogleClassroom do
  @moduledoc """
  Google Classroom adapter.

  Reads active courses and coursework for the authenticated student.
  Coursework whose title contains "test"/"quiz"/"exam" is imported as
  a `TestSchedule`; everything else is skipped.

  Service slug: `google_classroom`
  API: https://classroom.googleapis.com/v1
  """

  @behaviour FunSheep.Integrations.Provider

  require Logger

  @api_base "https://classroom.googleapis.com/v1"

  @impl true
  def service_id, do: "google_classroom"

  @impl true
  def default_scopes do
    [
      "https://www.googleapis.com/auth/classroom.courses.readonly",
      "https://www.googleapis.com/auth/classroom.coursework.me.readonly"
    ]
  end

  @impl true
  def supported?, do: true

  @impl true
  def list_courses(access_token, _opts \\ []) when is_binary(access_token) do
    http_get("#{@api_base}/courses?courseStates=ACTIVE", access_token)
    |> case do
      {:ok, %{"courses" => courses}} when is_list(courses) -> {:ok, courses}
      {:ok, %{}} -> {:ok, []}
      {:error, _} = err -> err
    end
  end

  @impl true
  def list_assignments(access_token, course_id, _opts \\ [])
      when is_binary(access_token) and is_binary(course_id) do
    http_get("#{@api_base}/courses/#{course_id}/courseWork", access_token)
    |> case do
      {:ok, %{"courseWork" => items}} when is_list(items) -> {:ok, items}
      {:ok, %{}} -> {:ok, []}
      {:error, _} = err -> err
    end
  end

  @impl true
  def normalize_course(%{"id" => external_id} = raw) do
    %{
      name: raw["name"] || "Untitled course",
      subject: raw["section"] || raw["name"] || "General",
      grade: parse_grade(raw),
      description: raw["description"],
      external_provider: service_id(),
      external_id: external_id,
      external_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: %{
        "source" => "google_classroom",
        "teacher_group_email" => raw["teacherGroupEmail"],
        "course_group_email" => raw["courseGroupEmail"],
        "enrollment_code" => raw["enrollmentCode"]
      }
    }
  end

  @impl true
  def normalize_assignment(
        %{"id" => external_id} = raw,
        local_course_id,
        user_role_id
      ) do
    title = raw["title"] || "Untitled"

    if test_like?(title, raw) do
      case parse_due_date(raw["dueDate"]) do
        {:ok, date} ->
          %{
            name: title,
            test_date: date,
            scope: %{"chapter_ids" => []},
            user_role_id: user_role_id,
            course_id: local_course_id,
            external_provider: service_id(),
            external_id: external_id,
            external_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }

        :error ->
          :skip
      end
    else
      :skip
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp http_get(url, access_token) do
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Google Classroom doesn't expose `workType == "TEST"` — coursework
  # is a bucket (ASSIGNMENT / SHORT_ANSWER_QUESTION / MULTIPLE_CHOICE_QUESTION).
  # Students and teachers almost always signal "this is a test" in the title,
  # so the heuristic is title-keyword match.
  @test_keywords ~w(test quiz exam midterm final assessment)

  defp test_like?(title, _raw) when is_binary(title) do
    down = String.downcase(title)
    Enum.any?(@test_keywords, &String.contains?(down, &1))
  end

  defp test_like?(_, _), do: false

  defp parse_due_date(%{"year" => y, "month" => m, "day" => d})
       when is_integer(y) and is_integer(m) and is_integer(d) do
    case Date.new(y, m, d) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  defp parse_due_date(_), do: :error

  # Classroom doesn't carry grade metadata explicitly; fall back to a
  # conservative "unknown" placeholder that still satisfies the
  # Course.changeset :grade requirement.
  defp parse_grade(%{"descriptionHeading" => heading}) when is_binary(heading) do
    case Regex.run(~r/grade\s*(\d{1,2}|K)/i, heading, capture: :all_but_first) do
      [g] -> normalize_grade(g)
      _ -> "Unknown"
    end
  end

  defp parse_grade(_), do: "Unknown"

  defp normalize_grade(g) do
    g
    |> String.trim()
    |> String.upcase()
    |> case do
      "K" -> "K"
      other -> other
    end
  end
end
