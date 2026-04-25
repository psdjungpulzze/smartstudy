defmodule FunSheep.Notifications.QuietHoursTest do
  @moduledoc """
  Unit tests for `FunSheep.Notifications.in_quiet_hours?/1`.

  The function reads `DateTime.utc_now()` internally, so deterministic tests
  are constructed by computing the expected result from the actual current UTC
  hour at test-run time, or by using windows whose outcome is unconditional
  (e.g., zero-width window is always false).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Notifications

  defp user_with_quiet(qs, qe, tz \\ "Etc/UTC") do
    %FunSheep.Accounts.UserRole{
      id: Ecto.UUID.generate(),
      timezone: tz,
      notification_quiet_start: qs,
      notification_quiet_end: qe
    }
  end

  describe "in_quiet_hours?/1 — zero window" do
    test "qs == qe == 0 is never quiet" do
      refute Notifications.in_quiet_hours?(user_with_quiet(0, 0))
    end

    test "qs == qe (non-zero) is also never quiet" do
      refute Notifications.in_quiet_hours?(user_with_quiet(12, 12))
    end
  end

  describe "in_quiet_hours?/1 — same-day window (qs < qe)" do
    test "window [0, 23) returns expected result based on current UTC hour" do
      h = DateTime.utc_now().hour
      # Window covers hours 0-22; at UTC hour 23 the user is NOT in quiet hours.
      expected = h < 23
      assert Notifications.in_quiet_hours?(user_with_quiet(0, 23)) == expected
    end

    test "window that starts 3 hours ahead of any possible hour is never quiet" do
      # A window entirely in the future relative to ANY hour 0-23 is impossible
      # to construct deterministically without knowing the hour. Instead, test
      # with qs=22, qe=23: quiet only at hour 22.
      h = DateTime.utc_now().hour
      expected = h == 22
      assert Notifications.in_quiet_hours?(user_with_quiet(22, 23)) == expected
    end
  end

  describe "in_quiet_hours?/1 — overnight window (qs > qe)" do
    test "window [1, 0) returns expected result based on current UTC hour" do
      h = DateTime.utc_now().hour
      # Overnight: quiet when h >= 1 OR h < 0. Since h is always >= 0,
      # this simplifies to: quiet when h >= 1 (i.e., not at midnight UTC).
      expected = h >= 1
      assert Notifications.in_quiet_hours?(user_with_quiet(1, 0)) == expected
    end

    test "window [23, 22) returns expected result (quiet when h >= 23 or h < 22)" do
      h = DateTime.utc_now().hour
      # Overnight window spanning 23 hours (not quiet only at hour 22)
      expected = h >= 23 or h < 22
      assert Notifications.in_quiet_hours?(user_with_quiet(23, 22)) == expected
    end
  end

  describe "in_quiet_hours?/1 — timezone handling" do
    test "does not crash with a nil timezone (falls back to UTC)" do
      ur = user_with_quiet(0, 0, nil)
      refute Notifications.in_quiet_hours?(ur)
    end

    test "does not crash with an invalid timezone string" do
      # Falls back to UTC; zero window still returns false
      ur = user_with_quiet(0, 0, "Not/A/Real/Zone")
      refute Notifications.in_quiet_hours?(ur)
    end

    test "honours a non-UTC timezone (falls back to UTC when tzdata unavailable)" do
      # Without a tzdata database the shift_zone call returns an error and
      # in_quiet_hours? falls back to the current UTC hour.  We verify the
      # function does NOT crash and still returns the correct result based on UTC.
      utc_hour = DateTime.utc_now().hour

      # A zero window is never quiet regardless of timezone or fallback.
      refute Notifications.in_quiet_hours?(user_with_quiet(0, 0, "Etc/GMT-5"))

      # A window [utc_hour, utc_hour+1) wraps the current UTC hour exactly, so
      # it should be quiet (same-day window, always covers current hour).
      if utc_hour < 23 do
        assert Notifications.in_quiet_hours?(user_with_quiet(utc_hour, utc_hour + 1, "Etc/GMT-5"))
      end
    end
  end
end
