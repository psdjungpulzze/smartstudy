defmodule FunSheep.InviteCodes do
  @moduledoc """
  Context for guardian invite codes — Flow B's parent-managed path
  (§5.2).

  Lifecycle:

    1. `create/2` — parent-side: produces a single-use 8-char code with
       a 14-day expiry, storing the child's display name / optional
       email. If `email` is present, also fires
       `Accounts.invite_guardian/3` so the child receives a traditional
       email invite in addition to being able to use the code.
    2. `redeem/2` — child-side: verifies code is active, creates the
       `student_guardian` row as `:active`, and stamps the invite code
       as redeemed by the child's `user_role_id`.
  """

  import Ecto.Query

  alias FunSheep.Accounts
  alias FunSheep.Accounts.{InviteCode, StudentGuardian, UserRole}
  alias FunSheep.Repo

  @doc """
  Creates a new invite code. Also fires a traditional
  `Accounts.invite_guardian/3` call when `child_email` is present so
  the flow degrades gracefully — whichever reaches the child first wins.
  """
  def create(guardian_id, attrs) when is_binary(guardian_id) do
    attrs = Map.put(attrs, :guardian_id, guardian_id)

    case %InviteCode{} |> InviteCode.create_changeset(attrs) |> Repo.insert() do
      {:ok, invite} ->
        maybe_send_email_invite(invite)
        {:ok, invite}

      {:error, cs} ->
        {:error, cs}
    end
  end

  defp maybe_send_email_invite(%InviteCode{
         child_email: email,
         guardian_id: gid,
         relationship_type: type
       })
       when is_binary(email) and email != "" do
    case Accounts.invite_guardian(gid, email, type) do
      {:ok, _} -> :ok
      {:error, :student_not_found} -> :ok
      {:error, :already_linked} -> :ok
      {:error, :already_invited} -> :ok
      _ -> :ok
    end
  end

  defp maybe_send_email_invite(_), do: :ok

  @doc "Fetches an invite code by its literal string."
  def get_by_code(code) when is_binary(code) do
    Repo.get_by(InviteCode, code: code)
  end

  @doc """
  Redeems a code for a child who has just signed in.

  Returns `{:ok, student_guardian}` on success, or an error tuple for
  expired/redeemed/mismatched codes.
  """
  def redeem(code, %UserRole{role: :student} = child) when is_binary(code) do
    Repo.transaction(fn -> do_redeem(code, child) end)
  end

  def redeem(_code, _child), do: {:error, :only_students_can_redeem}

  defp do_redeem(code, child) do
    invite = Repo.get_by(InviteCode, code: code)

    cond do
      is_nil(invite) ->
        Repo.rollback(:invalid_code)

      not InviteCode.active?(invite) ->
        Repo.rollback(:expired_or_redeemed)

      true ->
        link_and_stamp(invite, child)
    end
  end

  defp link_and_stamp(invite, child) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Upsert the student_guardian link as :active.
    existing =
      from(sg in StudentGuardian,
        where: sg.guardian_id == ^invite.guardian_id and sg.student_id == ^child.id
      )
      |> Repo.one()

    sg_result =
      case existing do
        %StudentGuardian{status: :active} = sg ->
          {:ok, sg}

        %StudentGuardian{} = sg ->
          StudentGuardian.changeset(sg, %{status: :active, accepted_at: now})
          |> Repo.update()

        nil ->
          %StudentGuardian{}
          |> StudentGuardian.changeset(%{
            guardian_id: invite.guardian_id,
            student_id: child.id,
            relationship_type: invite.relationship_type,
            status: :active,
            invited_at: invite.inserted_at,
            accepted_at: now
          })
          |> Repo.insert()
      end

    case sg_result do
      {:ok, student_guardian} ->
        {:ok, _} =
          invite
          |> InviteCode.redeem_changeset(%{
            redeemed_at: now,
            redeemed_by_user_role_id: child.id
          })
          |> Repo.update()

        student_guardian

      {:error, changeset} ->
        Repo.rollback({:link_failed, changeset})
    end
  end

  @doc "Lists active (unredeemed, unexpired) invite codes for a guardian."
  def list_active_for_guardian(guardian_id) do
    now = DateTime.utc_now()

    from(ic in InviteCode,
      where:
        ic.guardian_id == ^guardian_id and is_nil(ic.redeemed_at) and
          ic.expires_at > ^now,
      order_by: [desc: ic.inserted_at]
    )
    |> Repo.all()
  end
end
