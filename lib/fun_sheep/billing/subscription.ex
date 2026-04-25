defmodule FunSheep.Billing.Subscription do
  @moduledoc """
  Schema for locally cached subscription state.

  Tracks which plan a user is on and syncs with the
  Interactor Billing Server for payment management.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @plans ~w(free monthly annual)
  @statuses ~w(active cancelled past_due expired)

  schema "subscriptions" do
    field :plan, :string, default: "free"
    field :status, :string, default: "active"
    field :billing_subscription_id, :string
    field :stripe_customer_id, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :cancelled_at, :utc_datetime
    field :metadata, :map, default: %{}
    # Admin-granted bonus free tests, added on top of the base free-tier
    # lifetime cap. Used to comp users (support requests, beta feedback,
    # influencer accounts) without deleting usage history.
    field :bonus_free_tests, :integer, default: 0
    # List of catalog access tokens granted by this subscription.
    # Reserved for future premium catalog tier gating.
    field :catalog_access, {:array, :string}, default: []

    belongs_to :user_role, FunSheep.Accounts.UserRole

    # §3.1, §7.2 — payer-vs-beneficiary split.
    # `user_role` is the beneficiary (always the student).
    # `paid_by_user_role` is the payer (parent, or student self-purchasing).
    belongs_to :paid_by_user_role, FunSheep.Accounts.UserRole

    # §7.2 — links a paid sub back to the practice_request that produced it
    # (Flow A). Null for self-purchase or parent upfront purchase (Flow B).
    belongs_to :origin_practice_request, FunSheep.PracticeRequests.Request

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_role_id,
      :plan,
      :status,
      :billing_subscription_id,
      :stripe_customer_id,
      :current_period_start,
      :current_period_end,
      :cancelled_at,
      :metadata,
      :bonus_free_tests,
      :catalog_access,
      :paid_by_user_role_id,
      :origin_practice_request_id
    ])
    |> validate_required([:user_role_id, :plan, :status])
    |> validate_inclusion(:plan, @plans)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:bonus_free_tests, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_role_id)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:paid_by_user_role_id)
    |> foreign_key_constraint(:origin_practice_request_id)
  end

  def paid?(%__MODULE__{plan: plan, status: "active"}) when plan in ["monthly", "annual"],
    do: true

  def paid?(_), do: false
end
