defmodule FunSheep.Workers.TestUpcomingWorker do
  @moduledoc """
  Cron worker that runs daily at 08:00 UTC and sends test-countdown
  alerts to students (and their guardians) when a test is 3 days or
  1 day away.

  - T-3 alert (priority :high) is sent to the student and all active
    guardians who have `alerts_test_upcoming` enabled.
  - T-1 alert (priority :critical) is sent the same way but with
    more urgency in the copy.

  Days-until is computed from the window query in `Notifications`, which
  uses a ±1-hour window around T−3 and T−1 so DST clock shifts don't
  silently skip a test.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias FunSheep.{Accounts, Notifications}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    alerts = Notifications.upcoming_test_alerts()

    Logger.info("[TestUpcoming] found #{length(alerts)} upcoming test alert(s)")

    Enum.each(alerts, &send_alert/1)

    :ok
  end

  defp send_alert(%{test_date: test_date} = alert) do
    days_until = Date.diff(test_date, Date.utc_today())

    send_student_alert(alert, days_until)
    send_guardian_alerts(alert, days_until)
  end

  defp send_student_alert(%{student_id: student_id, test_name: name}, days_until) do
    {type, priority, body} = alert_copy(name, days_until)

    {:ok, _} =
      Notifications.enqueue(student_id,
        type: type,
        priority: priority,
        title: "Test in #{days_until} #{day_word(days_until)}",
        body: body,
        payload: %{days_until: days_until, test_name: name},
        channels: [:in_app, :push]
      )
  end

  defp send_guardian_alerts(
         %{student_id: student_id, test_name: name, student_name: student_name},
         days_until
       ) do
    guardian_links = Accounts.list_active_guardians_for_student(student_id)

    Enum.each(guardian_links, fn %{guardian: guardian} ->
      if guardian.alerts_test_upcoming do
        {type, priority, _body} = alert_copy(name, days_until)

        guardian_body =
          "#{student_name}'s #{name} is in #{days_until} #{day_word(days_until)}. " <>
            "Check their readiness on the dashboard."

        {:ok, _} =
          Notifications.enqueue(guardian.id,
            type: type,
            priority: priority,
            title: "#{student_name}'s test in #{days_until} #{day_word(days_until)}",
            body: guardian_body,
            payload: %{
              "days_until" => days_until,
              "test_name" => name,
              "student_id" => student_id
            },
            channels: [:in_app, :push]
          )
      end
    end)
  end

  defp alert_copy(name, 1) do
    {
      :test_upcoming_1d,
      0,
      "Your #{name} is tomorrow. Focus on your weakest skills today."
    }
  end

  defp alert_copy(name, _days) do
    {
      :test_upcoming_3d,
      1,
      "Your #{name} is in 3 days. Check your readiness and target weak areas."
    }
  end

  defp day_word(1), do: "day"
  defp day_word(_), do: "days"
end
