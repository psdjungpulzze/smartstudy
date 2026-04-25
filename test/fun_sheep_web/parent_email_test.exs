defmodule FunSheepWeb.ParentEmailTest do
  @moduledoc """
  Unit tests for `FunSheepWeb.ParentEmail.weekly_digest/2`.

  Tests that the email is addressed correctly, carries the right subject,
  renders mandatory content (minutes, unsubscribe link), and conditionally
  includes optional blocks (readiness change, prompt, upcoming tests).
  """

  use FunSheep.DataCase, async: true

  alias FunSheepWeb.ParentEmail
  alias FunSheep.Notifications.UnsubscribeToken

  defp build_digest(overrides \\ %{}) do
    guardian = %FunSheep.Accounts.UserRole{
      id: Ecto.UUID.generate(),
      display_name: "Jane Parent",
      email: "jane@test.com",
      role: :parent
    }

    student = %FunSheep.Accounts.UserRole{
      id: Ecto.UUID.generate(),
      display_name: "Alex Student",
      email: "alex@test.com",
      role: :student
    }

    defaults = %{
      guardian: guardian,
      student: student,
      minutes_this_week: 45,
      minutes_prev_week: 30,
      readiness_change: nil,
      top_improvement: nil,
      top_concern: nil,
      prompt: nil,
      upcoming_tests: [],
      unsubscribe_token: UnsubscribeToken.mint(guardian.id)
    }

    Map.merge(defaults, overrides)
  end

  describe "weekly_digest/2 — envelope" do
    test "subject includes the student's display_name" do
      digest = build_digest()
      email = ParentEmail.weekly_digest(digest)
      assert email.subject == "Weekly update: Alex Student"
    end

    test "subject uses fallback when display_name is nil" do
      digest = build_digest(%{student: %{build_digest().student | display_name: nil}})
      email = ParentEmail.weekly_digest(digest)
      assert email.subject =~ "your student"
    end

    test "email is addressed to the guardian" do
      digest = build_digest()
      email = ParentEmail.weekly_digest(digest)
      assert {"Jane Parent", "jane@test.com"} in email.to
    end

    test "custom from address is honoured" do
      digest = build_digest()
      email = ParentEmail.weekly_digest(digest, from: "custom@school.org")
      # Swoosh normalises a plain string address to {"", address}
      assert elem(email.from, 1) == "custom@school.org"
    end
  end

  describe "weekly_digest/2 — HTML body" do
    test "contains minutes studied this week" do
      digest = build_digest(%{minutes_this_week: 45, minutes_prev_week: 30})
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "45 min"
      assert email.html_body =~ "30 min"
    end

    test "contains the student name in the header" do
      digest = build_digest()
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "Alex Student"
    end

    test "includes readiness change when present and positive" do
      digest = build_digest(%{readiness_change: 5})
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "+5%"
    end

    test "includes readiness change when present and negative" do
      digest = build_digest(%{readiness_change: -3})
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "-3%"
    end

    test "omits readiness line when readiness_change is nil" do
      digest = build_digest(%{readiness_change: nil})
      email = ParentEmail.weekly_digest(digest)
      refute email.html_body =~ "Readiness change"
    end

    test "includes conversation prompt block when prompt present" do
      prompt = %{opener: "How did you feel about algebra?", rationale: "They struggled recently."}
      digest = build_digest(%{prompt: prompt})
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "Conversation starter"
      assert email.html_body =~ "How did you feel about algebra?"
      assert email.html_body =~ "They struggled recently."
    end

    test "omits prompt block when prompt is nil" do
      digest = build_digest(%{prompt: nil})
      email = ParentEmail.weekly_digest(digest)
      refute email.html_body =~ "Conversation starter"
    end

    test "includes upcoming tests block when tests are present" do
      test_date = Date.add(Date.utc_today(), 5)
      tests = [%{name: "Bio Final", test_date: test_date}]
      digest = build_digest(%{upcoming_tests: tests})
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "Upcoming"
      assert email.html_body =~ "Bio Final"
      assert email.html_body =~ Date.to_string(test_date)
    end

    test "omits upcoming block when tests list is empty" do
      digest = build_digest(%{upcoming_tests: []})
      email = ParentEmail.weekly_digest(digest)
      refute email.html_body =~ "Upcoming (14 days)"
    end

    test "includes unsubscribe link in HTML body" do
      digest = build_digest()
      email = ParentEmail.weekly_digest(digest)
      assert email.html_body =~ "/notifications/unsubscribe/"
    end

    test "escapes HTML special characters in student name" do
      student = %{build_digest().student | display_name: "<script>alert(1)</script>"}
      digest = build_digest(%{student: student})
      email = ParentEmail.weekly_digest(digest)
      refute email.html_body =~ "<script>"
      assert email.html_body =~ "&lt;script&gt;"
    end
  end

  describe "weekly_digest/2 — text body" do
    test "text body includes minutes studied" do
      digest = build_digest(%{minutes_this_week: 60, minutes_prev_week: 20})
      email = ParentEmail.weekly_digest(digest)
      assert email.text_body =~ "60 min"
      assert email.text_body =~ "20 min"
    end

    test "text body includes readiness change when present" do
      digest = build_digest(%{readiness_change: 10})
      email = ParentEmail.weekly_digest(digest)
      assert email.text_body =~ "+10%"
    end

    test "text body omits readiness line when nil" do
      digest = build_digest(%{readiness_change: nil})
      email = ParentEmail.weekly_digest(digest)
      refute email.text_body =~ "Readiness"
    end

    test "text body includes unsubscribe URL" do
      digest = build_digest()
      email = ParentEmail.weekly_digest(digest)
      assert email.text_body =~ "/notifications/unsubscribe/"
    end

    test "text body includes upcoming test names when present" do
      test_date = Date.add(Date.utc_today(), 2)
      tests = [%{name: "Chemistry Midterm", test_date: test_date}]
      digest = build_digest(%{upcoming_tests: tests})
      email = ParentEmail.weekly_digest(digest)
      assert email.text_body =~ "Chemistry Midterm"
    end

    test "text body includes prompt opener when present" do
      prompt = %{opener: "Did you review chapter 5?", rationale: "Chapter 5 is on the test."}
      digest = build_digest(%{prompt: prompt})
      email = ParentEmail.weekly_digest(digest)
      assert email.text_body =~ "Did you review chapter 5?"
    end
  end
end
