defmodule FunSheep.Accounts do
  @moduledoc """
  The Accounts context.

  Manages user roles (student, parent, teacher) and guardian relationships.
  Authentication is delegated to Interactor Account Server.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo
  alias FunSheep.Accounts.{UserRole, StudentGuardian}

  ## User Roles

  def list_user_roles do
    Repo.all(UserRole)
  end

  def get_user_role!(id), do: Repo.get!(UserRole, id)

  def get_user_role(id), do: Repo.get(UserRole, id)

  def get_user_role_by_interactor_id(interactor_user_id) do
    from(ur in UserRole,
      where: ur.interactor_user_id == ^interactor_user_id,
      order_by: [asc: ur.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def get_user_role_by_interactor_id_and_role(interactor_user_id, role)
      when is_binary(role) or is_atom(role) do
    role_atom =
      case role do
        r when is_atom(r) -> r
        r when is_binary(r) -> safe_to_role_atom(r)
      end

    case role_atom do
      nil -> nil
      r -> Repo.get_by(UserRole, interactor_user_id: interactor_user_id, role: r)
    end
  end

  def list_user_roles_by_interactor_id(interactor_user_id) do
    from(ur in UserRole,
      where: ur.interactor_user_id == ^interactor_user_id,
      order_by: [asc: ur.inserted_at]
    )
    |> Repo.all()
  end

  defp safe_to_role_atom("student"), do: :student
  defp safe_to_role_atom("parent"), do: :parent
  defp safe_to_role_atom("teacher"), do: :teacher
  defp safe_to_role_atom("admin"), do: :admin
  defp safe_to_role_atom(_), do: nil

  def create_user_role(attrs \\ %{}) do
    %UserRole{}
    |> UserRole.changeset(attrs)
    |> Repo.insert()
  end

  def update_user_role(%UserRole{} = user_role, attrs) do
    user_role
    |> UserRole.changeset(attrs)
    |> Repo.update()
  end

  def delete_user_role(%UserRole{} = user_role) do
    Repo.delete(user_role)
  end

  def change_user_role(%UserRole{} = user_role, attrs \\ %{}) do
    UserRole.changeset(user_role, attrs)
  end

  ## Student Guardians

  @doc """
  Returns true when the given guardian user_role is linked to the student
  user_role via an `:active` student_guardians row.

  This is the centralised authorization check for parent-facing data-fetching
  functions (spec §9.1). Call it at the edge of every context function that
  takes a `student_id` in a parent flow. Do not trust the LiveView.
  """
  def guardian_has_access?(guardian_id, student_id)
      when is_binary(guardian_id) and is_binary(student_id) do
    Repo.exists?(
      from sg in StudentGuardian,
        where:
          sg.guardian_id == ^guardian_id and
            sg.student_id == ^student_id and
            sg.status == :active
    )
  end

  def guardian_has_access?(_, _), do: false

  def list_student_guardians do
    Repo.all(StudentGuardian)
  end

  def get_student_guardian!(id), do: Repo.get!(StudentGuardian, id)

  def list_guardians_for_student(student_id) do
    from(sg in StudentGuardian,
      where: sg.student_id == ^student_id and sg.status == :active,
      preload: [:guardian]
    )
    |> Repo.all()
  end

  def list_students_for_guardian(guardian_id) do
    from(sg in StudentGuardian,
      where: sg.guardian_id == ^guardian_id and sg.status == :active,
      preload: [:student]
    )
    |> Repo.all()
  end

  def create_student_guardian(attrs \\ %{}) do
    %StudentGuardian{}
    |> StudentGuardian.changeset(attrs)
    |> Repo.insert()
  end

  def update_student_guardian(%StudentGuardian{} = student_guardian, attrs) do
    student_guardian
    |> StudentGuardian.changeset(attrs)
    |> Repo.update()
  end

  def delete_student_guardian(%StudentGuardian{} = student_guardian) do
    Repo.delete(student_guardian)
  end

  def change_student_guardian(%StudentGuardian{} = student_guardian, attrs \\ %{}) do
    StudentGuardian.changeset(student_guardian, attrs)
  end

  ## Guardian Invite/Accept Flow

  @doc """
  Invites a student (by email) to be linked to a guardian.
  Creates a pending student_guardian record.
  """
  def invite_guardian(guardian_id, student_email, relationship_type) do
    case Repo.get_by(UserRole, email: student_email, role: :student) do
      nil ->
        {:error, :student_not_found}

      student ->
        # Check for existing active or pending link
        existing =
          from(sg in StudentGuardian,
            where:
              sg.guardian_id == ^guardian_id and
                sg.student_id == ^student.id and
                sg.status in [:active, :pending]
          )
          |> Repo.one()

        case existing do
          nil ->
            create_student_guardian(%{
              guardian_id: guardian_id,
              student_id: student.id,
              relationship_type: relationship_type,
              status: :pending,
              invited_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          %StudentGuardian{status: :active} ->
            {:error, :already_linked}

          %StudentGuardian{status: :pending} ->
            {:error, :already_invited}
        end
    end
  end

  @doc """
  Student-initiated invite: links this student to a guardian (parent or
  teacher) identified by email.

  Resolves the guardian's email in three ways:

    1. **Account-resolved** — a `UserRole` with that email and the
       requested role exists → create a pending `StudentGuardian` row
       pointing at them. The guardian accepts from their `/guardians`
       inbox on next sign-in.

    2. **Email-only** — no matching `UserRole` exists → create a
       pending row with `guardian_id: nil`, `invited_email: email`,
       and a 14-day `invite_token`, then enqueue a delivery job so the
       address receives a claim link at `/guardian-invite/<token>`.

    3. **Already linked / already invited** — return the matching
       `{:error, :already_linked}` or `{:error, :already_invited}`.

  Errors:
    * `{:error, :invalid_email}` — blank / malformed input
    * `{:error, :already_linked}` — active link already exists
    * `{:error, :already_invited}` — pending invite already exists
    * `{:error, Ecto.Changeset.t()}` — insert failed
  """
  def invite_guardian_by_student(student_id, guardian_email, relationship_type)
      when is_binary(student_id) and is_binary(guardian_email) and
             relationship_type in [:parent, :teacher] do
    normalized = guardian_email |> String.trim() |> String.downcase()

    cond do
      normalized == "" ->
        {:error, :invalid_email}

      not String.contains?(normalized, "@") ->
        {:error, :invalid_email}

      true ->
        do_invite_guardian_by_student(student_id, normalized, relationship_type)
    end
  end

  defp do_invite_guardian_by_student(student_id, email, relationship_type) do
    guardian = Repo.get_by(UserRole, email: email, role: relationship_type)

    existing = find_existing_link_for_student(student_id, guardian, email)

    case {existing, guardian} do
      {%StudentGuardian{status: :active}, _} ->
        {:error, :already_linked}

      {%StudentGuardian{status: :pending}, _} ->
        {:error, :already_invited}

      {nil, %UserRole{} = g} ->
        create_student_guardian(%{
          guardian_id: g.id,
          student_id: student_id,
          relationship_type: relationship_type,
          status: :pending,
          invited_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {nil, nil} ->
        create_email_invite(student_id, email, relationship_type)
    end
  end

  defp find_existing_link_for_student(student_id, %UserRole{id: guardian_id}, _email) do
    from(sg in StudentGuardian,
      where:
        sg.student_id == ^student_id and sg.guardian_id == ^guardian_id and
          sg.status in [:active, :pending]
    )
    |> Repo.one()
  end

  defp find_existing_link_for_student(student_id, nil, email) do
    from(sg in StudentGuardian,
      where:
        sg.student_id == ^student_id and sg.invited_email == ^email and
          is_nil(sg.guardian_id) and sg.status in [:active, :pending]
    )
    |> Repo.one()
  end

  defp create_email_invite(student_id, email, relationship_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    token = generate_invite_token()
    expires_at = DateTime.add(now, 14 * 24 * 60 * 60, :second)

    attrs = %{
      student_id: student_id,
      relationship_type: relationship_type,
      status: :pending,
      invited_at: now,
      invited_email: email,
      invite_token: token,
      invite_token_expires_at: expires_at
    }

    case create_student_guardian(attrs) do
      {:ok, sg} ->
        enqueue_guardian_invite_email(sg)
        {:ok, sg}

      other ->
        other
    end
  end

  defp generate_invite_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp enqueue_guardian_invite_email(%StudentGuardian{id: id}) do
    %{student_guardian_id: id}
    |> FunSheep.Workers.GuardianInviteEmailWorker.new()
    |> Oban.insert()
  end

  @doc """
  Fetches a pending email-invite by its token, preloaded with the student.

  Returns `{:ok, sg}` when the token matches an unexpired pending row,
  or `{:error, reason}` for `:not_found`, `:expired`, or `:consumed`.
  """
  def fetch_pending_guardian_invite_by_token(token) when is_binary(token) do
    case Repo.get_by(StudentGuardian, invite_token: token) |> Repo.preload(:student) do
      nil ->
        {:error, :not_found}

      %StudentGuardian{status: :pending, invite_token_expires_at: exp} = sg
      when not is_nil(exp) ->
        if DateTime.compare(DateTime.utc_now(), exp) == :gt do
          {:error, :expired}
        else
          {:ok, sg}
        end

      %StudentGuardian{status: :pending} = sg ->
        {:ok, sg}

      %StudentGuardian{} ->
        {:error, :consumed}
    end
  end

  @doc """
  Claims a pending email-invite on behalf of the logged-in guardian.

  Sets `guardian_id` to the claimer, clears the token, and marks the
  link `:active` (the guardian's explicit click on the tokenised link
  counts as consent — no separate accept step).

  Returns `{:error, :relationship_mismatch}` if the claimer's role
  disagrees with the invite's `relationship_type`.
  """
  def claim_guardian_invite_by_token(token, %UserRole{role: role} = guardian)
      when is_binary(token) and role in [:parent, :teacher] do
    with {:ok, sg} <- fetch_pending_guardian_invite_by_token(token),
         :ok <- check_relationship_match(sg, role) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      result =
        sg
        |> StudentGuardian.changeset(%{
          guardian_id: guardian.id,
          status: :active,
          accepted_at: now,
          invite_token: nil,
          invite_token_expires_at: nil
        })
        |> Repo.update()

      case result do
        {:ok, updated_sg} ->
          enqueue_referral_credit_check(updated_sg)
          {:ok, updated_sg}

        error ->
          error
      end
    end
  end

  def claim_guardian_invite_by_token(_, _), do: {:error, :not_a_guardian}

  defp check_relationship_match(%StudentGuardian{relationship_type: rt}, role) when rt == role,
    do: :ok

  defp check_relationship_match(_, _), do: {:error, :relationship_mismatch}

  @doc """
  Accepts a pending guardian invite. Sets status to :active and records accepted_at.
  """
  def accept_guardian_invite(student_guardian_id) do
    case Repo.get(StudentGuardian, student_guardian_id) do
      nil ->
        {:error, :not_found}

      %StudentGuardian{status: :pending} = sg ->
        result =
          update_student_guardian(sg, %{
            status: :active,
            accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })

        case result do
          {:ok, updated_sg} ->
            enqueue_referral_credit_check(updated_sg)
            {:ok, updated_sg}

          error ->
            error
        end

      %StudentGuardian{} ->
        {:error, :not_pending}
    end
  end

  @doc """
  Rejects a pending guardian invite. Sets status to :revoked.
  """
  def reject_guardian_invite(student_guardian_id) do
    case Repo.get(StudentGuardian, student_guardian_id) do
      nil ->
        {:error, :not_found}

      %StudentGuardian{status: :pending} = sg ->
        update_student_guardian(sg, %{status: :revoked})

      %StudentGuardian{} ->
        {:error, :not_pending}
    end
  end

  @doc """
  Revokes an active or pending guardian link.
  """
  def revoke_guardian(student_guardian_id) do
    case Repo.get(StudentGuardian, student_guardian_id) do
      nil ->
        {:error, :not_found}

      %StudentGuardian{status: :revoked} ->
        {:error, :already_revoked}

      %StudentGuardian{} = sg ->
        update_student_guardian(sg, %{status: :revoked})
    end
  end

  @doc """
  Lists pending invites for a student (with guardian preloaded).
  """
  def list_pending_invites_for_student(student_id) do
    from(sg in StudentGuardian,
      where: sg.student_id == ^student_id and sg.status == :pending,
      preload: [:guardian]
    )
    |> Repo.all()
  end

  @doc """
  Lists active guardians for a student (alias for list_guardians_for_student).
  """
  def list_active_guardians_for_student(student_id) do
    list_guardians_for_student(student_id)
  end

  @doc """
  Returns the active guardians for a student as `[UserRole.t()]`.

  Used by `FunSheep.PracticeRequests` for Flow A's guardian picker. Per
  spec §6.3 and §7.4 Flow C, teachers must never appear in the picker
  for a billing flow — pass `only: :parent` to exclude them.

  Options:
    * `:only` — `:parent` or `:teacher`, restricts the `relationship_type`
  """
  def list_active_guardian_roles_for_student(student_id, opts \\ []) do
    query =
      from(sg in StudentGuardian,
        join: ur in assoc(sg, :guardian),
        where: sg.student_id == ^student_id and sg.status == :active,
        order_by: [asc: sg.inserted_at],
        select: ur
      )

    query =
      case Keyword.get(opts, :only) do
        nil ->
          query

        type when type in [:parent, :teacher] ->
          where(query, [sg, _ur], sg.relationship_type == ^type)
      end

    Repo.all(query)
  end

  @doc """
  Returns a single "primary" guardian for a student — parents preferred
  over teachers, oldest active link first. Returns `nil` if none found.

  Used by §4.4 request-builder modal for auto-selection when only one
  parent is linked, and by the §4.8 fallback to identify the single
  guardian to direct a reminder to.
  """
  def find_primary_guardian(student_id) do
    case list_active_guardian_roles_for_student(student_id, only: :parent) do
      [parent | _] -> parent
      [] -> list_active_guardian_roles_for_student(student_id, only: :teacher) |> List.first()
    end
  end

  @doc """
  Finds or creates a user_role by interactor_user_id, then updates profile fields.
  Used during course creation wizard to persist demographics.
  """
  def upsert_user_profile(interactor_user_id, attrs) do
    case get_user_role_by_interactor_id(interactor_user_id) do
      nil ->
        create_user_role(Map.put(attrs, :interactor_user_id, interactor_user_id))

      existing ->
        update_user_role(existing, attrs)
    end
  end

  ## User Role Lookups

  @doc """
  Gets a user role by email.
  """
  def get_user_role_by_email(email) do
    Repo.get_by(UserRole, email: email)
  end

  ## Admin queries

  @doc """
  Paginated list of user_role rows for the admin UI.

  ## Options
    * `:search` — case-insensitive substring match on email or display_name
    * `:role` — filter by role atom or string
    * `:limit` (default 25), `:offset` (default 0)
  """
  def list_users_for_admin(opts \\ []) do
    opts
    |> admin_users_query()
    |> order_by([ur], desc: ur.inserted_at)
    |> limit(^Keyword.get(opts, :limit, 25))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  @doc "Counts rows matching the same filters used by `list_users_for_admin/1`."
  def count_users_for_admin(opts \\ []) do
    opts
    |> admin_users_query()
    |> select([ur], count(ur.id))
    |> Repo.one()
  end

  @doc "Counts all user_role rows grouped by role. Returns `%{role => count}`."
  def count_users_by_role do
    from(ur in UserRole,
      group_by: ur.role,
      select: {ur.role, count(ur.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp admin_users_query(opts) do
    search = Keyword.get(opts, :search)
    role = Keyword.get(opts, :role)

    UserRole
    |> maybe_filter_role(role)
    |> maybe_filter_search(search)
  end

  defp maybe_filter_role(query, nil), do: query

  defp maybe_filter_role(query, role) when is_atom(role) do
    from(ur in query, where: ur.role == ^role)
  end

  defp maybe_filter_role(query, role) when is_binary(role) do
    case safe_to_role_atom(role) do
      nil -> query
      r -> from(ur in query, where: ur.role == ^r)
    end
  end

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, term) when is_binary(term) do
    pattern = "%#{term}%"

    from(ur in query,
      where: ilike(ur.email, ^pattern) or ilike(ur.display_name, ^pattern)
    )
  end

  ## Onboarding

  @doc """
  Marks a student's onboarding as complete by setting `onboarding_completed_at`.
  """
  def complete_onboarding(%UserRole{} = user_role) do
    user_role
    |> Ecto.Changeset.change(
      onboarding_completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
  end

  @doc """
  Returns true if the user_role has completed onboarding.
  """
  def onboarding_complete?(%UserRole{onboarding_completed_at: nil}), do: false
  def onboarding_complete?(%UserRole{}), do: true

  defp enqueue_referral_credit_check(%StudentGuardian{
         id: sg_id,
         guardian_id: guardian_id,
         relationship_type: :teacher
       })
       when not is_nil(guardian_id) do
    %{"teacher_user_role_id" => guardian_id, "student_guardian_id" => sg_id}
    |> FunSheep.Workers.CreditReferralCheckWorker.new()
    |> Oban.insert()
  end

  defp enqueue_referral_credit_check(_), do: :ok
end
