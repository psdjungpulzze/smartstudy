defmodule FunSheep.Admin.UserDetail do
  @moduledoc """
  Aggregator for the `/admin/users/:id` page.

  Combines data from multiple contexts (accounts, courses, audit log,
  ai_calls) into a single view-model map so the LiveView can stay dumb.
  Interactor-backed sections (subscription, profile, credentials) are
  represented by placeholder maps here — they light up when Phases 2.2 /
  3.2 / 3.3 ship.
  """

  import Ecto.Query, warn: false

  alias FunSheep.{Accounts, Admin, Repo}
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Admin.AuditLog
  alias FunSheep.Courses.Course

  @default_activity_limit 50
  @default_audit_limit 25
  @ai_window_days 30

  @type aggregate :: %{
          user: UserRole.t(),
          courses_owned: [map()],
          activity_timeline: [map()],
          audit_trail: [AuditLog.t()],
          ai_usage: map(),
          subscription: map(),
          interactor_profile: map(),
          credentials: map()
        }

  @spec load(binary()) :: aggregate()
  def load(user_role_id) do
    user = Accounts.get_user_role!(user_role_id)

    %{
      user: user,
      courses_owned: list_courses_owned(user),
      activity_timeline: build_activity_timeline(user),
      audit_trail: list_audit_trail(user),
      ai_usage: summarize_ai_usage(user),
      subscription: placeholder_subscription(),
      interactor_profile: placeholder_profile(),
      credentials: placeholder_credentials()
    }
  end

  ## --- Courses ---------------------------------------------------------

  defp list_courses_owned(%UserRole{} = user) do
    Course
    |> where([c], c.created_by_id == ^user.id)
    |> order_by([c], desc: c.inserted_at)
    |> limit(25)
    |> Repo.all()
  end

  ## --- Activity timeline ----------------------------------------------

  defp build_activity_timeline(%UserRole{} = user) do
    audit_entries =
      from(l in AuditLog,
        where: l.target_id == ^user.id,
        order_by: [desc: l.inserted_at],
        limit: @default_activity_limit
      )
      |> Repo.all()
      |> Enum.map(fn log ->
        %{
          kind: :audit,
          at: log.inserted_at,
          summary: audit_log_summary(log),
          raw: log
        }
      end)

    course_entries =
      Course
      |> where([c], c.created_by_id == ^user.id)
      |> order_by([c], desc: c.inserted_at)
      |> limit(@default_activity_limit)
      |> Repo.all()
      |> Enum.map(fn c ->
        %{
          kind: :course_created,
          at: c.inserted_at,
          summary: "Created course: #{c.name || c.subject || c.id}",
          raw: c
        }
      end)

    (audit_entries ++ course_entries)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(@default_activity_limit)
  end

  defp audit_log_summary(%AuditLog{action: action, actor_label: actor}) do
    "#{format_action(action)} by #{actor}"
  end

  defp format_action("user.suspend"), do: "Suspended"
  defp format_action("user.unsuspend"), do: "Reinstated"
  defp format_action("user.promote_to_admin"), do: "Promoted to admin"
  defp format_action("user.demote_admin"), do: "Demoted from admin"
  defp format_action("impersonation.start"), do: "Impersonation started"
  defp format_action("impersonation.stop"), do: "Impersonation ended"
  defp format_action(other), do: other

  ## --- Audit trail (last N admin actions targeting this user) ---------

  defp list_audit_trail(%UserRole{} = user) do
    from(l in AuditLog,
      where: l.target_id == ^user.id,
      order_by: [desc: l.inserted_at],
      limit: @default_audit_limit
    )
    |> Repo.all()
  end

  ## --- AI usage (last 30d) --------------------------------------------

  defp summarize_ai_usage(%UserRole{id: user_id}) do
    since = DateTime.add(DateTime.utc_now(), -@ai_window_days * 86_400, :second)

    row =
      from(c in "ai_calls",
        where:
          c.inserted_at >= ^since and
            fragment("(?)->>'user_role_id' = ?", c.metadata, ^user_id),
        select: %{
          calls: count(c.id),
          total_tokens: coalesce(sum(c.total_tokens), 0),
          top_assistant:
            fragment(
              "MODE() WITHIN GROUP (ORDER BY ?)",
              c.assistant_name
            )
        }
      )
      |> Repo.one()

    %{
      calls: (row && row.calls) || 0,
      total_tokens: (row && row.total_tokens) || 0,
      top_assistant: row && row.top_assistant,
      window_days: @ai_window_days
    }
  rescue
    _ -> %{calls: 0, total_tokens: 0, top_assistant: nil, window_days: @ai_window_days}
  end

  ## --- Placeholders (filled in by later phases) ------------------------

  defp placeholder_subscription do
    %{
      available?: false,
      message: "Subscription details land once the billing surface ships (plan Phase 2.2)."
    }
  end

  defp placeholder_profile do
    %{
      available?: false,
      message: "Interactor profile debugger lands in plan Phase 3.3."
    }
  end

  defp placeholder_credentials do
    %{
      available?: false,
      message: "Per-user credential status lands in plan Phase 3.2."
    }
  end

  ## --- Audit helper for page view -------------------------------------

  @doc """
  Records an `admin.user.view` audit entry. Called from the LiveView mount
  so every admin peek at a user surface is logged (the page exposes PII).
  """
  def record_view(%UserRole{} = target, actor) do
    Admin.record(%{
      actor_user_role_id: actor_user_role_id(actor),
      actor_label: actor_label(actor),
      action: "admin.user.view",
      target_type: "user_role",
      target_id: target.id,
      metadata: %{"email" => target.email}
    })
  end

  defp actor_user_role_id(%{"user_role_id" => id}) when is_binary(id), do: id
  defp actor_user_role_id(_), do: nil

  defp actor_label(%{"email" => email}) when is_binary(email), do: "admin:#{email}"
  defp actor_label(_), do: "admin:unknown"
end
