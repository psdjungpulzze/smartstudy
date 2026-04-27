defmodule FunSheep.Notifications.NotificationTest do
  @moduledoc """
  Unit tests for the `Notification` schema changeset and accessor functions.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.ContentFixtures
  alias FunSheep.Notifications.Notification

  setup do
    student = ContentFixtures.create_user_role(%{role: :student})
    %{student: student}
  end

  defp valid_attrs(student_id) do
    %{
      user_role_id: student_id,
      type: :streak_at_risk,
      channel: :in_app,
      body: "You have a streak at risk.",
      scheduled_for: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  describe "changeset/2 — valid" do
    test "accepts valid required fields", %{student: s} do
      changeset = Notification.changeset(%Notification{}, valid_attrs(s.id))
      assert changeset.valid?
    end

    test "accepts all optional fields", %{student: s} do
      attrs =
        valid_attrs(s.id)
        |> Map.merge(%{
          title: "Streak alert",
          priority: 1,
          payload: %{"streak" => 3},
          status: :sent,
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      changeset = Notification.changeset(%Notification{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 — required fields" do
    test "rejects missing body", %{student: s} do
      attrs = valid_attrs(s.id) |> Map.delete(:body)
      changeset = Notification.changeset(%Notification{}, attrs)
      assert changeset.errors[:body]
    end

    test "rejects missing type", %{student: s} do
      attrs = valid_attrs(s.id) |> Map.delete(:type)
      changeset = Notification.changeset(%Notification{}, attrs)
      assert changeset.errors[:type]
    end

    test "rejects missing channel", %{student: s} do
      attrs = valid_attrs(s.id) |> Map.delete(:channel)
      changeset = Notification.changeset(%Notification{}, attrs)
      assert changeset.errors[:channel]
    end

    test "rejects missing scheduled_for", %{student: s} do
      attrs = valid_attrs(s.id) |> Map.delete(:scheduled_for)
      changeset = Notification.changeset(%Notification{}, attrs)
      assert changeset.errors[:scheduled_for]
    end
  end

  describe "changeset/2 — validations" do
    test "rejects priority outside 0-3", %{student: s} do
      changeset =
        Notification.changeset(%Notification{}, Map.put(valid_attrs(s.id), :priority, 5))

      assert changeset.errors[:priority]
    end

    test "accepts priority 0 (critical)", %{student: s} do
      changeset =
        Notification.changeset(%Notification{}, Map.put(valid_attrs(s.id), :priority, 0))

      assert changeset.valid?
    end

    test "rejects body longer than 500 characters", %{student: s} do
      long_body = String.duplicate("x", 501)

      changeset =
        Notification.changeset(%Notification{}, Map.put(valid_attrs(s.id), :body, long_body))

      assert changeset.errors[:body]
    end

    test "rejects title longer than 200 characters", %{student: s} do
      long_title = String.duplicate("t", 201)

      changeset =
        Notification.changeset(%Notification{}, Map.put(valid_attrs(s.id), :title, long_title))

      assert changeset.errors[:title]
    end

    test "accepts title of exactly 200 characters", %{student: s} do
      title = String.duplicate("t", 200)

      changeset =
        Notification.changeset(%Notification{}, Map.put(valid_attrs(s.id), :title, title))

      assert changeset.valid?
    end
  end

  describe "types/0 and channels/0" do
    test "types/0 returns the full list of notification types" do
      types = Notification.types()
      assert :streak_at_risk in types
      assert :test_upcoming_3d in types
      assert :test_upcoming_1d in types
      assert :weekly_digest in types
      assert length(types) == 19
    end

    test "channels/0 returns all supported channels" do
      assert Notification.channels() == [:push, :email, :in_app, :sms]
    end
  end
end
