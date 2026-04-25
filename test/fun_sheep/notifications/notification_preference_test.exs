defmodule FunSheep.Notifications.NotificationPreferenceTest do
  @moduledoc """
  Tests for `FunSheep.Notifications.get_preference/3` and
  `FunSheep.Notifications.upsert_preference/1`.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Notifications, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Notifications.NotificationPreference

  setup do
    student = ContentFixtures.create_user_role(%{role: :student})
    %{student: student}
  end

  describe "upsert_preference/1" do
    test "creates a new channel-level preference row", %{student: s} do
      assert {:ok, %NotificationPreference{enabled: false}} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :push,
                 enabled: false,
                 frequency_tier: :standard
               })
    end

    test "creates a type-specific preference row", %{student: s} do
      assert {:ok, %NotificationPreference{notification_type: "streak_at_risk"}} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :push,
                 notification_type: "streak_at_risk",
                 enabled: true,
                 frequency_tier: :standard
               })
    end

    test "updates an existing preference row", %{student: s} do
      {:ok, _} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :push,
          enabled: true,
          frequency_tier: :standard
        })

      {:ok, updated} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :push,
          enabled: false,
          frequency_tier: :light
        })

      assert updated.enabled == false
      assert updated.frequency_tier == :light
    end

    test "rejects an invalid frequency_tier", %{student: s} do
      assert {:error, changeset} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :push,
                 enabled: true,
                 frequency_tier: :invalid_tier
               })

      assert changeset.errors[:frequency_tier]
    end

    test "rejects quiet_start outside 0-23", %{student: s} do
      assert {:error, changeset} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :in_app,
                 enabled: true,
                 frequency_tier: :standard,
                 quiet_start: 25
               })

      assert changeset.errors[:quiet_start]
    end

    test "rejects quiet_end outside 0-23", %{student: s} do
      assert {:error, changeset} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :in_app,
                 enabled: true,
                 frequency_tier: :standard,
                 quiet_end: 24
               })

      assert changeset.errors[:quiet_end]
    end

    test "rejects preferred_hour outside 0-23", %{student: s} do
      assert {:error, changeset} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :push,
                 enabled: true,
                 frequency_tier: :standard,
                 preferred_hour: -1
               })

      assert changeset.errors[:preferred_hour]
    end

    test "accepts preferred_hour within 0-23", %{student: s} do
      assert {:ok, pref} =
               Notifications.upsert_preference(%{
                 user_role_id: s.id,
                 channel: :push,
                 enabled: true,
                 frequency_tier: :standard,
                 preferred_hour: 9
               })

      assert pref.preferred_hour == 9
    end

    test "accepts all valid frequency tiers", %{student: s} do
      for {tier, i} <- Enum.with_index([:off, :light, :standard, :all]) do
        assert {:ok, _} =
                 Notifications.upsert_preference(%{
                   user_role_id: s.id,
                   channel: :push,
                   notification_type: "type_#{i}",
                   enabled: true,
                   frequency_tier: tier
                 })
      end
    end

    test "enforces uniqueness on (user_role_id, channel, notification_type)", %{student: s} do
      {:ok, _} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :email,
          enabled: true,
          frequency_tier: :standard
        })

      # Direct DB insert to test the constraint (upsert avoids it intentionally).
      changeset =
        %NotificationPreference{}
        |> NotificationPreference.changeset(%{
          user_role_id: s.id,
          channel: :email,
          enabled: false,
          frequency_tier: :light
        })

      assert {:error, cs} = Repo.insert(changeset)
      assert cs.errors[:user_role_id] || cs.errors[:notification_type] || cs.errors[:channel]
    end
  end

  describe "get_preference/3" do
    test "returns nil when no preference row exists", %{student: s} do
      assert is_nil(Notifications.get_preference(s.id, :push))
    end

    test "returns the channel-level default when no type given", %{student: s} do
      {:ok, pref} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :push,
          enabled: false,
          frequency_tier: :standard
        })

      result = Notifications.get_preference(s.id, :push)
      assert result.id == pref.id
      assert result.enabled == false
    end

    test "returns type-specific row when it exists", %{student: s} do
      # channel default (disabled)
      {:ok, _default} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :push,
          enabled: false,
          frequency_tier: :standard
        })

      # type-specific override (enabled)
      {:ok, override} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :push,
          notification_type: "streak_at_risk",
          enabled: true,
          frequency_tier: :standard
        })

      result = Notifications.get_preference(s.id, :push, :streak_at_risk)
      assert result.id == override.id
      assert result.enabled == true
    end

    test "falls back to channel default when type-specific row is absent", %{student: s} do
      {:ok, default_pref} =
        Notifications.upsert_preference(%{
          user_role_id: s.id,
          channel: :push,
          enabled: false,
          frequency_tier: :standard
        })

      result = Notifications.get_preference(s.id, :push, :streak_at_risk)
      assert result.id == default_pref.id
    end
  end
end
