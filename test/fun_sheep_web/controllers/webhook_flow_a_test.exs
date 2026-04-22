defmodule FunSheepWeb.WebhookFlowATest do
  @moduledoc """
  Covers the webhook extension that stamps `paid_by_user_role_id` +
  `origin_practice_request_id` on subscription activation, and
  transitions the originating practice_request to `:accepted`
  (§4.7, §7.2).
  """

  use FunSheepWeb.ConnCase, async: false

  alias FunSheep.{Accounts, Billing, PracticeRequests}
  alias FunSheep.Billing.Subscription
  alias FunSheep.Repo

  defp create_role(role, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "iuid_#{System.unique_integer([:positive])}",
      role: role,
      email: "#{role}_#{System.unique_integer([:positive])}@t.com",
      display_name: "#{role}"
    }

    {:ok, r} = Accounts.create_user_role(Map.merge(defaults, attrs))
    r
  end

  defp link_parent(parent, student) do
    {:ok, _} =
      Accounts.create_student_guardian(%{
        guardian_id: parent.id,
        student_id: student.id,
        relationship_type: :parent,
        status: :active,
        invited_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    :ok
  end

  test "subscription.activated with metadata stamps paid_by and accepts the request", %{
    conn: conn
  } do
    student = create_role(:student, %{display_name: "Kid"})
    parent = create_role(:parent, %{display_name: "Mom"})
    link_parent(parent, student)

    {:ok, request} = PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})

    body = %{
      "type" => "subscription.activated",
      "data" => %{
        "subscriber_id" => student.interactor_user_id,
        "plan_name" => "annual",
        "subscription_id" => "sub_abc123",
        "stripe_customer_id" => "cus_xyz789",
        "metadata" => %{
          "practice_request_id" => request.id,
          "paid_by_interactor_user_id" => parent.interactor_user_id
        }
      }
    }

    conn = post(conn, ~p"/api/webhooks/interactor", body)
    assert json_response(conn, 200) == %{"status" => "activated"}

    sub = Billing.get_subscription(student.id)
    assert %Subscription{plan: "annual", status: "active"} = sub
    assert sub.paid_by_user_role_id == parent.id
    assert sub.origin_practice_request_id == request.id

    updated_request = Repo.get!(FunSheep.PracticeRequests.Request, request.id)
    assert updated_request.status == :accepted
  end

  test "subscription.activated without metadata still works for direct purchase", %{conn: conn} do
    student = create_role(:student)

    body = %{
      "type" => "subscription.activated",
      "data" => %{
        "subscriber_id" => student.interactor_user_id,
        "plan_name" => "monthly",
        "subscription_id" => "sub_direct"
      }
    }

    conn = post(conn, ~p"/api/webhooks/interactor", body)
    assert json_response(conn, 200) == %{"status" => "activated"}

    sub = Billing.get_subscription(student.id)
    # No Flow A metadata → paid_by falls back to the beneficiary (self-purchase).
    assert sub.paid_by_user_role_id == student.id
    assert is_nil(sub.origin_practice_request_id)
  end
end
