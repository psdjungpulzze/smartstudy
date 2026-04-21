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
  Accepts a pending guardian invite. Sets status to :active and records accepted_at.
  """
  def accept_guardian_invite(student_guardian_id) do
    case Repo.get(StudentGuardian, student_guardian_id) do
      nil ->
        {:error, :not_found}

      %StudentGuardian{status: :pending} = sg ->
        update_student_guardian(sg, %{
          status: :active,
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

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
end
