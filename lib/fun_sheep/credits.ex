defmodule FunSheep.Credits do
  @moduledoc """
  The Credits context for the Wool Credits system.

  Teachers earn "Wool Credits" by growing their classroom and contributing content.
  Credits are stored as quarter-units (4 quarter-units = 1 credit).
  The ledger is append-only — never update or delete wool_credits rows.
  """

  import Ecto.Query
  alias FunSheep.Repo
  alias FunSheep.Credits.{WoolCredit, CreditTransfer}
  alias FunSheep.Billing

  ## Balance

  @doc """
  Returns the current balance in whole credits (floor div by 4).
  """
  def get_balance(user_role_id) do
    div(get_balance_quarter_units(user_role_id), 4)
  end

  @doc """
  Returns the raw quarter-unit balance (clamped at 0).
  """
  def get_balance_quarter_units(user_role_id) do
    result =
      from(w in WoolCredit,
        where: w.user_role_id == ^user_role_id,
        select: sum(w.delta)
      )
      |> Repo.one()

    max(result || 0, 0)
  end

  ## Ledger

  @doc """
  Returns the last N ledger entries for a user, ordered newest first.
  """
  def list_ledger(user_role_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(w in WoolCredit,
      where: w.user_role_id == ^user_role_id,
      order_by: [desc: w.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## Awarding

  @doc """
  Awards quarter-units to a teacher. Idempotent by source_ref_id.

  Returns `{:error, :already_awarded}` when the same source_ref_id has
  already been processed.
  """
  def award_credit(
        teacher_user_role_id,
        source,
        quarter_units,
        source_ref_id \\ nil,
        metadata \\ %{}
      ) do
    if already_awarded?(source_ref_id) do
      {:error, :already_awarded}
    else
      %WoolCredit{}
      |> WoolCredit.changeset(%{
        user_role_id: teacher_user_role_id,
        delta: quarter_units,
        source: source,
        source_ref_id: source_ref_id,
        metadata: metadata
      })
      |> Repo.insert()
    end
  end

  ## Counting

  @doc """
  Returns the number of referral WoolCredit rows for a teacher.
  """
  def count_referral_awards(teacher_user_role_id) do
    from(w in WoolCredit,
      where: w.user_role_id == ^teacher_user_role_id and w.source == "referral",
      select: count(w.id)
    )
    |> Repo.one()
    |> then(&(&1 || 0))
  end

  @doc """
  Returns the count of active students for a teacher (via student_guardians).
  """
  def count_active_students(teacher_user_role_id) do
    count =
      from(sg in FunSheep.Accounts.StudentGuardian,
        where: sg.guardian_id == ^teacher_user_role_id and sg.status == :active,
        select: count(sg.id)
      )
      |> Repo.one()

    {:ok, count || 0}
  end

  ## Transfers

  @doc """
  Transfers N whole credits from one user to another.

  Atomically creates a `credit_transfer` record plus two `wool_credits` rows
  (debit and credit). Returns `{:error, :insufficient_balance}` when the
  sender does not have enough credits.
  """
  def transfer_credits(from_user_role_id, to_user_role_id, credits, note \\ nil)
      when is_integer(credits) and credits > 0 do
    quarter_units = credits * 4

    case get_balance_quarter_units(from_user_role_id) do
      bal when bal < quarter_units ->
        {:error, :insufficient_balance}

      _ ->
        case Repo.get(FunSheep.Accounts.UserRole, to_user_role_id) do
          nil ->
            {:error, :invalid_recipient}

          %{suspended_at: ts} when not is_nil(ts) ->
            {:error, :invalid_recipient}

          _ ->
            Repo.transaction(fn ->
              transfer =
                %CreditTransfer{}
                |> CreditTransfer.changeset(%{
                  from_user_role_id: from_user_role_id,
                  to_user_role_id: to_user_role_id,
                  amount_quarter_units: quarter_units,
                  note: note
                })
                |> Repo.insert!()

              %WoolCredit{}
              |> WoolCredit.changeset(%{
                user_role_id: from_user_role_id,
                delta: -quarter_units,
                source: "transfer_out",
                source_ref_id: transfer.id,
                metadata: %{}
              })
              |> Repo.insert!()

              %WoolCredit{}
              |> WoolCredit.changeset(%{
                user_role_id: to_user_role_id,
                delta: quarter_units,
                source: "transfer_in",
                source_ref_id: transfer.id,
                metadata: %{}
              })
              |> Repo.insert!()

              transfer
            end)
        end
    end
  end

  ## Redemption

  @doc """
  Redeems N whole credits for the user's own subscription extension.

  Each credit extends the subscription by 30 days.
  """
  def redeem_for_subscription(user_role_id, credits)
      when is_integer(credits) and credits > 0 do
    quarter_units = credits * 4

    case get_balance_quarter_units(user_role_id) do
      bal when bal < quarter_units ->
        {:error, :insufficient_balance}

      _ ->
        Repo.transaction(fn ->
          {:ok, sub} = Billing.get_or_create_subscription(user_role_id)
          days = credits * 30

          new_end =
            case sub do
              %{status: "active", current_period_end: end_dt} when not is_nil(end_dt) ->
                DateTime.add(end_dt, days * 86_400, :second)

              _ ->
                DateTime.add(DateTime.utc_now(), days * 86_400, :second)
            end

          {:ok, updated_sub} =
            Billing.update_subscription(sub, %{
              plan: "monthly",
              status: "active",
              current_period_start: sub.current_period_start || DateTime.utc_now(),
              current_period_end: new_end
            })

          %WoolCredit{}
          |> WoolCredit.changeset(%{
            user_role_id: user_role_id,
            delta: -quarter_units,
            source: "redemption",
            source_ref_id: updated_sub.id,
            metadata: %{}
          })
          |> Repo.insert!()

          updated_sub
        end)
    end
  end

  ## Progress Dashboard

  @doc """
  Returns progress toward the next credit for each earning category.

  Used by the teacher dashboard to show how close they are to earning credits.
  """
  def credit_progress(teacher_user_role_id) do
    {:ok, student_count} = count_active_students(teacher_user_role_id)
    referral_batches_awarded = count_referral_awards(teacher_user_role_id)
    current_batch = div(student_count, 10)
    students_in_current_batch = rem(student_count, 10)

    material_quarter_units =
      from(w in WoolCredit,
        where: w.user_role_id == ^teacher_user_role_id and w.source == "material_upload",
        select: sum(w.delta)
      )
      |> Repo.one()
      |> then(&max(&1 || 0, 0))

    test_quarter_units =
      from(w in WoolCredit,
        where: w.user_role_id == ^teacher_user_role_id and w.source == "test_created",
        select: sum(w.delta)
      )
      |> Repo.one()
      |> then(&max(&1 || 0, 0))

    %{
      referral_batches_awarded: referral_batches_awarded,
      students: %{
        current: student_count,
        batch_progress: students_in_current_batch,
        next_at: (current_batch + 1) * 10
      },
      materials: %{
        quarter_units: rem(material_quarter_units, 4),
        next_at_units: 4 - rem(material_quarter_units, 4)
      },
      tests: %{
        quarter_units: rem(test_quarter_units, 4),
        next_at_units: 4 - rem(test_quarter_units, 4)
      }
    }
  end

  ## Private

  defp already_awarded?(nil), do: false

  defp already_awarded?(source_ref_id) do
    Repo.exists?(from(w in WoolCredit, where: w.source_ref_id == ^source_ref_id))
  end
end
