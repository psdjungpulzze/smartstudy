defmodule FunSheep.Admin do
  @moduledoc """
  Admin context: audit logging and (future) platform management primitives.

  The audit log is append-only; writes are best-effort (a failed insert is
  logged but does not abort the caller's operation) because dropping the
  action would be worse than missing its audit record.
  """
  import Ecto.Query, warn: false
  require Logger

  alias FunSheep.Repo
  alias FunSheep.Admin.AuditLog

  @type actor ::
          %{required(:user_role_id) => binary() | nil, required(:label) => String.t()}
          | %{optional(:ip) => String.t()}

  @doc """
  Records an admin action.

  ## Required keys
  - `:actor_label` — human-readable description of who took the action,
    e.g. `"admin:peter@interactor.com"` or `"mix-task:admin.grant"`.
  - `:action` — short snake_case verb, e.g. `"user.suspend"`.

  ## Optional keys
  - `:actor_user_role_id` — local `UserRole.id` when the actor is a logged-in admin.
  - `:target_type`, `:target_id` — what was acted upon.
  - `:metadata` — arbitrary details (before/after, reason).
  - `:ip` — remote IP, when available.
  """
  @spec record(map()) :: {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def record(attrs) when is_map(attrs) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _} = ok ->
        ok

      {:error, changeset} = err ->
        Logger.error("Failed to write admin audit log: #{inspect(changeset.errors)}")
        err
    end
  end

  @doc """
  Lists audit log rows, newest first. Intended for the admin audit view.
  """
  def list_audit_logs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    from(l in AuditLog,
      order_by: [desc: l.inserted_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:actor]
    )
    |> Repo.all()
  end

  @doc "Counts total audit log rows."
  def count_audit_logs do
    Repo.aggregate(AuditLog, :count)
  end

  ## Privileged mutations — each one records an audit row.

  alias FunSheep.Accounts
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Billing
  alias FunSheep.Billing.Subscription
  alias FunSheep.Courses
  alias FunSheep.Courses.Course

  @doc """
  Suspends a user account. Login continues to succeed at Interactor but the
  `:require_auth` hook blocks suspended users from reaching any app page.
  """
  def suspend_user(%UserRole{} = target, actor) do
    with {:ok, updated} <-
           Accounts.update_user_role(target, %{
             suspended_at: DateTime.utc_now() |> DateTime.truncate(:second)
           }) do
      record_actor_event(actor, "user.suspend", target, %{
        "email" => target.email,
        "role" => Atom.to_string(target.role)
      })

      {:ok, updated}
    end
  end

  @doc "Reverses `suspend_user/2`."
  def unsuspend_user(%UserRole{} = target, actor) do
    with {:ok, updated} <- Accounts.update_user_role(target, %{suspended_at: nil}) do
      record_actor_event(actor, "user.unsuspend", target, %{"email" => target.email})
      {:ok, updated}
    end
  end

  @doc """
  Promotes a user to admin by inserting a local admin UserRole row for the
  same Interactor user. Does NOT push `metadata.role = "admin"` to
  Interactor — use `mix funsheep.admin.grant` for full bootstrap.

  This function is for the in-app "promote" button that adds the local row
  after the Interactor-side claim has already been set by an operator.
  """
  def promote_to_admin(%UserRole{} = target, actor) do
    case Accounts.get_user_role_by_interactor_id_and_role(target.interactor_user_id, :admin) do
      %UserRole{} = existing ->
        {:ok, existing}

      nil ->
        case Accounts.create_user_role(%{
               interactor_user_id: target.interactor_user_id,
               role: :admin,
               email: target.email,
               display_name: target.display_name
             }) do
          {:ok, admin_row} = ok ->
            record_actor_event(actor, "user.promote_to_admin", target, %{
              "email" => target.email,
              "local_admin_user_role_id" => admin_row.id
            })

            ok

          err ->
            err
        end
    end
  end

  @doc "Removes the local admin UserRole row (other roles remain untouched)."
  def demote_admin(%UserRole{role: :admin} = admin_row, actor) do
    with {:ok, _} = ok <- Accounts.delete_user_role(admin_row) do
      record_actor_event(actor, "user.demote_admin", admin_row, %{
        "email" => admin_row.email
      })

      ok
    end
  end

  def demote_admin(%UserRole{}, _actor), do: {:error, :not_admin}

  @doc """
  Sets the bonus free tests granted to a user (added on top of the
  default lifetime cap). Pass `0` to revoke any prior grant.

  Only meaningful for free-plan students; paid plans are unlimited.
  Returns `{:error, :invalid_bonus}` for non-integer or negative values.
  """
  def set_bonus_free_tests(%UserRole{} = target, bonus, actor)
      when is_integer(bonus) and bonus >= 0 do
    {:ok, sub} = Billing.get_or_create_subscription(target.id)
    previous = sub.bonus_free_tests || 0

    case Billing.update_subscription(sub, %{bonus_free_tests: bonus}) do
      {:ok, %Subscription{} = updated} ->
        record_actor_event(actor, "user.set_bonus_free_tests", target, %{
          "email" => target.email,
          "previous_bonus" => previous,
          "new_bonus" => bonus
        })

        {:ok, updated}

      err ->
        err
    end
  end

  def set_bonus_free_tests(%UserRole{}, _bonus, _actor), do: {:error, :invalid_bonus}

  @doc "Deletes a course and every dependent record. Irreversible."
  def delete_course(%Course{} = course, actor) do
    with {:ok, deleted} <- Courses.delete_course(course) do
      record_actor_event(actor, "course.delete", course, %{
        "name" => course.name,
        "subject" => course.subject
      })

      {:ok, deleted}
    end
  end

  alias FunSheep.Content
  alias FunSheep.Content.UploadedMaterial
  alias FunSheep.Workers.OCRMaterialWorker

  @doc "Deletes an uploaded material and its OCR artifacts. Audit-logged."
  def delete_material(%UploadedMaterial{} = material, actor) do
    with {:ok, deleted} <- Content.delete_uploaded_material(material) do
      record_actor_event(actor, "material.delete", material, %{
        "file_name" => material.file_name,
        "course_id" => material.course_id
      })

      {:ok, deleted}
    end
  end

  ## Impersonation

  @impersonation_ttl_seconds 30 * 60

  @doc "Returns the impersonation TTL in seconds."
  def impersonation_ttl_seconds, do: @impersonation_ttl_seconds

  @doc """
  Validates whether `admin` may impersonate `target` and records the start
  event. Returns session data to store; callers are responsible for writing
  it into the conn session.

  Blocks: self-impersonation, impersonating another admin, suspended admins,
  and suspended targets (suspended users can't be impersonated — use the
  audit log to investigate their activity instead).
  """
  def start_impersonation(
        %UserRole{role: :admin, suspended_at: nil} = admin,
        %UserRole{} = target
      ) do
    cond do
      admin.id == target.id ->
        {:error, :cannot_impersonate_self}

      target.role == :admin ->
        {:error, :cannot_impersonate_admin}

      UserRole.suspended?(target) ->
        {:error, :target_suspended}

      true ->
        record_actor_event(admin, "impersonation.start", target, %{
          "target_email" => target.email,
          "target_role" => Atom.to_string(target.role)
        })

        expires_at =
          DateTime.utc_now()
          |> DateTime.add(@impersonation_ttl_seconds, :second)
          |> DateTime.truncate(:second)

        {:ok,
         %{
           "impersonated_user_role_id" => target.id,
           "real_admin_user_role_id" => admin.id,
           "impersonation_expires_at" => DateTime.to_iso8601(expires_at)
         }}
    end
  end

  def start_impersonation(%UserRole{}, _), do: {:error, :not_admin}

  @doc "Records the end of an impersonation session. Call before clearing the session keys."
  def stop_impersonation(%UserRole{} = admin, %UserRole{} = target, reason \\ :manual) do
    record_actor_event(admin, "impersonation.stop", target, %{
      "target_email" => target.email,
      "reason" => to_string(reason)
    })

    :ok
  end

  @doc """
  Parses an ISO8601 string and returns true if the timestamp is in the past.
  Any parse error is treated as expired (fail secure).
  """
  def impersonation_expired?(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> DateTime.compare(DateTime.utc_now(), dt) != :lt
      _ -> true
    end
  end

  def impersonation_expired?(_), do: true

  @doc """
  Re-enqueues the OCR pipeline for a material. Use when a page failed and
  should be retried after a config fix. Audit-logged.
  """
  def rerun_ocr(%UploadedMaterial{} = material, actor) do
    job =
      %{material_id: material.id, course_id: material.course_id}
      |> OCRMaterialWorker.new()

    case Oban.insert(job) do
      {:ok, _} = ok ->
        record_actor_event(actor, "material.rerun_ocr", material, %{
          "file_name" => material.file_name
        })

        ok

      err ->
        err
    end
  end

  ## Helpers

  defp record_actor_event(actor, action, target, metadata) do
    record(%{
      actor_user_role_id: actor_id(actor),
      actor_label: actor_label(actor),
      action: action,
      target_type: target_type(target),
      target_id: target_id(target),
      metadata: metadata
    })
  end

  defp actor_id(%{"user_role_id" => id}) when is_binary(id), do: id
  defp actor_id(%UserRole{id: id}), do: id
  defp actor_id(_), do: nil

  defp actor_label(%{"email" => email}) when is_binary(email), do: "admin:#{email}"
  defp actor_label(%UserRole{email: email}) when is_binary(email), do: "admin:#{email}"
  defp actor_label(%{label: label}) when is_binary(label), do: label
  defp actor_label(_), do: "admin:unknown"

  defp target_type(%UserRole{}), do: "user_role"
  defp target_type(%Course{}), do: "course"
  defp target_type(%UploadedMaterial{}), do: "uploaded_material"
  defp target_type(%{__struct__: mod}), do: mod |> Module.split() |> List.last()
  defp target_type(_), do: nil

  defp target_id(%{id: id}), do: to_string(id)
  defp target_id(_), do: nil
end
