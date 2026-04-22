defmodule FunSheepWeb.Emails.ParentRequestEmail do
  @moduledoc """
  Renders the "your kid asked for more practice" email.

  See `~/s/funsheep-subscription-flows.md` §4.6.1 and §8.1.

  PR 2 ships Variant A ("The rare parent-win") with minimal structural
  layout so the worker can actually send. PR 3 will style the HTML to
  production quality and wire the `:parent_request_email_variant`
  feature flag for the pending B variant.

  **Guardrails (§8.2)**: every metric rendered here comes from the
  request's immutable activity snapshot (`request.metadata`). We never
  fabricate: if there's no upcoming test, we omit that block entirely;
  if the streak is 1 day, we say 1 day.
  """

  import Swoosh.Email

  alias FunSheep.Accounts.UserRole
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo

  @from_name "FunSheep"
  @from_email "noreply@funsheep.com"

  @doc """
  Builds a Swoosh `%Email{}` for the given request.

  The request must have `:student` and `:guardian` either preloaded or
  loadable. If the guardian has no email on file, returns `{:error, :no_guardian_email}`.
  """
  def build(%Request{} = request) do
    request = Repo.preload(request, [:student, :guardian])

    case request.guardian do
      %UserRole{email: email, display_name: parent_name} when is_binary(email) ->
        {:ok, render(request, email, parent_name)}

      _ ->
        {:error, :no_guardian_email}
    end
  end

  defp render(%Request{} = request, to_email, parent_name) do
    %{
      student_name: request.student.display_name,
      parent_first: first_name(parent_name),
      reason: reason_copy(request),
      snapshot: request.metadata
    }
    |> then(fn assigns ->
      new()
      |> to({parent_name || "FunSheep parent", to_email})
      |> from({@from_name, @from_email})
      |> subject(subject_for(assigns.student_name))
      |> text_body(render_text(assigns))
      |> html_body(render_html(assigns))
    end)
  end

  defp subject_for(student_name) do
    # §8.1 Variant A subject line.
    "#{student_name} just asked you for more practice 💚"
  end

  defp first_name(nil), do: "there"

  defp first_name(full_name) do
    full_name |> String.split(" ", parts: 2) |> List.first() || "there"
  end

  defp reason_copy(%Request{
         reason_code: :upcoming_test,
         metadata: %{"upcoming_test" => %{"name" => n}}
       })
       when is_binary(n) do
    "I want to ace my #{n}"
  end

  defp reason_copy(%Request{reason_code: :upcoming_test}), do: "I want to ace my upcoming test"

  defp reason_copy(%Request{reason_code: :weak_topic}),
    do: "I'm working on my weakest topic and want to get it right"

  defp reason_copy(%Request{reason_code: :streak}), do: "I'm on a streak and I want to keep going"

  defp reason_copy(%Request{reason_code: :other, reason_text: text})
       when is_binary(text) and text != "",
       do: text

  defp reason_copy(_), do: "I want more practice this week"

  defp render_text(assigns) do
    """
    Hi #{assigns.parent_first},

    #{assigns.student_name} just sent you a request from FunSheep:

      "#{assigns.reason}"

    They've hit this week's free practice cap and asked you to
    unlock more. This happens to be the kind of message most
    parents never get.

    Here's what #{assigns.student_name} has actually done on FunSheep:

    #{evidence_lines(assigns.snapshot, assigns.student_name, format: :text)}

      [ Unlock unlimited for #{assigns.student_name} ]
      https://funsheep.com/subscription?request=#{assigns[:request_id] || ""}

    Two plans — both unlock unlimited practice for #{assigns.student_name}:

      • $90 / year — best value ($7.50 / month equivalent)
      • $30 / month — cancel any time

    You can also say not right now — #{assigns.student_name} will be told
    kindly, and they can ask again later.

    Thanks,
    The FunSheep team
    """
  end

  defp render_html(assigns) do
    # PR 2: minimal structural HTML. PR 3 styles it with Tailwind-friendly
    # inline CSS and the Interactor design system.
    """
    <div style="font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
      <p>Hi #{assigns.parent_first},</p>

      <p><strong>#{assigns.student_name}</strong> just sent you a request from FunSheep:</p>

      <blockquote style="border-left:3px solid #4CD964;padding:8px 16px;color:#333;">
        "#{html_escape(assigns.reason)}"
      </blockquote>

      <p>They've hit this week's free practice cap and asked you to unlock more. This happens to be the kind of message most parents never get.</p>

      <p><strong>Here's what #{assigns.student_name} has actually done on FunSheep:</strong></p>

      #{evidence_lines(assigns.snapshot, assigns.student_name, format: :html)}

      <p style="text-align:center;margin:32px 0;">
        <a href="https://funsheep.com/subscription?request=#{assigns[:request_id] || ""}"
           style="background:#4CD964;color:#fff;padding:12px 24px;border-radius:9999px;text-decoration:none;font-weight:600;">
          Unlock unlimited for #{assigns.student_name}
        </a>
      </p>

      <p style="color:#555;font-size:14px;">
        Two plans — both unlock unlimited practice:<br>
        • <strong>$90 / year</strong> — best value ($7.50 / month equivalent)<br>
        • $30 / month — cancel any time
      </p>

      <p style="color:#777;font-size:13px;">
        You can also say not right now — #{assigns.student_name} will be told kindly, and they can ask again later.
      </p>

      <p style="color:#999;font-size:12px;margin-top:32px;">
        FunSheep · This email was sent because #{assigns.student_name} is linked to your parent account.
      </p>
    </div>
    """
  end

  defp evidence_lines(snapshot, student_name, format: :text) do
    lines =
      [
        line(snapshot["streak_days"], "#{snapshot["streak_days"]}-day streak"),
        line(
          snapshot["weekly_minutes"],
          "#{snapshot["weekly_minutes"]} min of focused practice this week"
        ),
        line(
          snapshot["weekly_sessions"],
          "#{snapshot["weekly_sessions"]} study sessions this week"
        ),
        line(snapshot["accuracy_pct"], "#{snapshot["accuracy_pct"]}% accuracy"),
        upcoming_line(snapshot["upcoming_test"], student_name)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.map_join(lines, "\n", fn l -> "  • " <> l end)
  end

  defp evidence_lines(snapshot, student_name, format: :html) do
    lines =
      [
        line(snapshot["streak_days"], "#{snapshot["streak_days"]}-day streak"),
        line(
          snapshot["weekly_minutes"],
          "#{snapshot["weekly_minutes"]} min of focused practice this week"
        ),
        line(
          snapshot["weekly_sessions"],
          "#{snapshot["weekly_sessions"]} study sessions this week"
        ),
        line(snapshot["accuracy_pct"], "#{snapshot["accuracy_pct"]}% accuracy"),
        upcoming_line(snapshot["upcoming_test"], student_name)
      ]
      |> Enum.reject(&is_nil/1)

    "<ul>" <> Enum.map_join(lines, "", fn l -> "<li>#{html_escape(l)}</li>" end) <> "</ul>"
  end

  # §8.2: only include a line if the metric is meaningful. A zero streak
  # or 0 minutes is real — we show it. `nil` from a missing snapshot key
  # gets skipped rather than fabricated.
  defp line(nil, _text), do: nil
  defp line(_value, text), do: text

  defp upcoming_line(nil, _student_name), do: nil

  defp upcoming_line(%{"name" => name, "days_away" => days}, _student_name) when days >= 0 do
    "#{name} is in #{days} days"
  end

  defp upcoming_line(_, _), do: nil

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp html_escape(other), do: to_string(other)
end
