defmodule FunSheepWeb.DevProgressController do
  @moduledoc """
  Dev-only helper to drive the `FunSheep.Progress` broadcast sequence for
  visual testing of the regeneration progress panel. NOT mounted in prod.
  """
  use FunSheepWeb, :controller

  alias FunSheep.Progress
  alias FunSheep.Progress.Event

  # Drive one chapter job through preparing → generating → saving with N ticks
  # and then succeed. Query params: course_id, chapter_id, label, total (default 10)
  # Optional: delay_ms (per tick, default 400), hold_ms (sleep before succeeded, default 0)
  def broadcast(conn, params) do
    course_id = Map.fetch!(params, "course_id")
    chapter_id = Map.fetch!(params, "chapter_id")
    label = Map.get(params, "label", "Chapter")
    total = params |> Map.get("total", "10") |> String.to_integer()
    delay_ms = params |> Map.get("delay_ms", "400") |> String.to_integer()
    hold_ms = params |> Map.get("hold_ms", "0") |> String.to_integer()
    terminal = Map.get(params, "terminal", "succeed")

    Task.start(fn ->
      base =
        Event.new(
          job_id: "chapter:#{chapter_id}",
          topic_type: :course,
          topic_id: course_id,
          scope: :question_regeneration,
          phase_total: 3,
          subject_id: chapter_id,
          subject_label: label
        )

      e1 = Progress.phase(base, :preparing, "Preparing chapter context", 1)
      Process.sleep(500)
      e2 = Progress.phase(e1, :generating, "Generating questions with AI", 2)
      Process.sleep(500)
      e3 = Progress.phase(e2, :saving, "Saving questions", 3)

      e_final =
        Enum.reduce(1..total, e3, fn i, ev ->
          Process.sleep(delay_ms)
          Progress.tick(ev, i, total, "questions")
        end)

      if hold_ms > 0, do: Process.sleep(hold_ms)

      case terminal do
        "succeed" -> Progress.succeeded(e_final, "questions", total)
        "fail" -> Progress.failed(e_final, :ai_unavailable, "AI service unavailable")
        _ -> :ok
      end
    end)

    json(conn, %{ok: true, course_id: course_id, chapter_id: chapter_id})
  end
end
