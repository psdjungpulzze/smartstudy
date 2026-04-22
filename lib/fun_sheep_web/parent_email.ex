defmodule FunSheepWeb.ParentEmail do
  @moduledoc """
  Swoosh email template for the weekly parent digest (spec §8.1).

  Real numbers only. If a digest field is missing we simply don't render
  that block — we never invent a value. The unsubscribe link is a
  signed token (§8.4) and does not require auth.
  """

  import Swoosh.Email
  use FunSheepWeb, :html

  alias FunSheep.Notifications

  @type digest :: Notifications.digest()

  @doc """
  Builds a `%Swoosh.Email{}` for the weekly digest. `from` defaults to
  a neutral noreply address that can be overridden via app config.
  """
  @spec weekly_digest(digest(), keyword()) :: Swoosh.Email.t()
  def weekly_digest(digest, opts \\ []) do
    from_address =
      Keyword.get(
        opts,
        :from,
        Application.get_env(:fun_sheep, :mailer_from, "noreply@funsheep.local")
      )

    subject = "Weekly update: #{digest.student.display_name || "your student"}"

    new()
    |> to({digest.guardian.display_name || "", digest.guardian.email})
    |> from(from_address)
    |> subject(subject)
    |> html_body(render_html(digest))
    |> text_body(render_text(digest))
  end

  defp render_html(digest) do
    unsubscribe_url = unsubscribe_url(digest.unsubscribe_token)

    """
    <html><body style="font-family: system-ui, sans-serif; max-width: 480px; margin: 0 auto; color: #111;">
    <div style="background: #E8F8EB; border-radius: 16px; padding: 24px; margin-bottom: 16px;">
      <p style="font-size: 12px; color: #256029; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 4px;">Weekly digest</p>
      <h1 style="margin: 0; font-size: 22px;">#{esc(digest.student.display_name || "Your student")}</h1>
    </div>
    #{section("This week", [minutes_line(digest), readiness_line(digest)])}
    #{prompt_block(digest.prompt)}
    #{upcoming_block(digest.upcoming_tests)}
    <p style="font-size: 12px; color: #888; text-align: center; margin-top: 32px;">
      <a href="#{unsubscribe_url}" style="color: #888;">Unsubscribe</a>
      · student local time · real-activity summary
    </p>
    </body></html>
    """
  end

  defp render_text(digest) do
    lines = [
      "Weekly update — #{digest.student.display_name || "your student"}",
      "",
      "This week: #{digest.minutes_this_week} min studied (prev #{digest.minutes_prev_week} min).",
      readiness_line_plain(digest.readiness_change),
      "",
      prompt_plain(digest.prompt),
      "",
      upcoming_plain(digest.upcoming_tests),
      "",
      "Unsubscribe: #{unsubscribe_url(digest.unsubscribe_token)}"
    ]

    lines |> Enum.reject(&(&1 == "")) |> Enum.join("\n")
  end

  defp section(title, lines) do
    """
    <div style="border-radius: 16px; border: 1px solid #eee; padding: 16px; margin-bottom: 12px;">
      <p style="font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 8px;">#{esc(title)}</p>
      #{Enum.join(lines, "")}
    </div>
    """
  end

  defp minutes_line(digest),
    do:
      "<p style=\"margin: 0 0 4px; font-size: 14px;\">#{digest.minutes_this_week} min studied (prev #{digest.minutes_prev_week} min)</p>"

  defp readiness_line(%{readiness_change: nil}), do: ""

  defp readiness_line(%{readiness_change: change}),
    do: "<p style=\"margin: 0; font-size: 14px;\">Readiness change: #{format_change(change)}</p>"

  defp readiness_line_plain(nil), do: ""
  defp readiness_line_plain(change), do: "Readiness change: #{format_change(change)}"

  defp prompt_block(nil), do: ""

  defp prompt_block(prompt) do
    """
    <div style="border-radius: 16px; border: 1px solid #eee; background: #fafafa; padding: 16px; margin-bottom: 12px;">
      <p style="font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 8px;">Conversation starter</p>
      <p style="margin: 0 0 8px; font-size: 14px; font-style: italic;">&ldquo;#{esc(prompt.opener)}&rdquo;</p>
      <p style="margin: 0; font-size: 12px; color: #666;">#{esc(prompt.rationale)}</p>
    </div>
    """
  end

  defp prompt_plain(nil), do: ""
  defp prompt_plain(prompt), do: "Opener: \"#{prompt.opener}\" — #{prompt.rationale}"

  defp upcoming_block([]), do: ""

  defp upcoming_block(tests) do
    items =
      tests
      |> Enum.take(3)
      |> Enum.map_join("", fn t ->
        "<li style=\"font-size: 14px; margin-bottom: 4px;\">#{esc(t.name)} — #{Date.to_string(t.test_date)}</li>"
      end)

    """
    <div style="border-radius: 16px; border: 1px solid #eee; padding: 16px;">
      <p style="font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 8px;">Upcoming (14 days)</p>
      <ul style="padding-left: 18px; margin: 0;">#{items}</ul>
    </div>
    """
  end

  defp upcoming_plain([]), do: ""

  defp upcoming_plain(tests) do
    "Upcoming: " <>
      (tests
       |> Enum.take(3)
       |> Enum.map_join(", ", fn t -> "#{t.name} (#{Date.to_string(t.test_date)})" end))
  end

  defp unsubscribe_url(token) do
    "#{FunSheepWeb.Endpoint.url()}/notifications/unsubscribe/#{token}"
  end

  defp format_change(change) when is_number(change) and change > 0, do: "+#{change}%"
  defp format_change(change) when is_number(change), do: "#{change}%"
  defp format_change(_), do: "—"

  defp esc(nil), do: ""

  defp esc(s) when is_binary(s),
    do: Phoenix.HTML.html_escape(s) |> Phoenix.HTML.safe_to_string()

  defp esc(s), do: esc(to_string(s))
end
