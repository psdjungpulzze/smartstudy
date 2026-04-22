defmodule FunSheepWeb.Emails.ParentRequestEmailTest do
  @moduledoc """
  Covers the Flow A parent email renderer. Verifies §8.2 "no fake
  content" guardrails: we never fabricate data the snapshot doesn't
  provide; we include only real metrics.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests.Request
  alias FunSheep.Repo
  alias FunSheepWeb.Emails.ParentRequestEmail

  defp create_role(role, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: role,
      email: "#{role}_#{System.unique_integer([:positive])}@t.com",
      display_name: "#{role}"
    }

    {:ok, r} = Accounts.create_user_role(Map.merge(defaults, attrs))
    r
  end

  defp build_request(attrs) do
    student = create_role(:student, %{display_name: "Lia"})
    parent = create_role(:parent, %{display_name: "Anna Smith", email: "anna@t.com"})

    metadata =
      Map.merge(
        %{
          "streak_days" => 5,
          "weekly_minutes" => 95,
          "weekly_sessions" => 12,
          "accuracy_pct" => 82.5,
          "upcoming_test" => nil,
          "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        attrs[:metadata] || %{}
      )

    {:ok, req} =
      Request.create_changeset(%Request{}, %{
        student_id: student.id,
        guardian_id: parent.id,
        reason_code: attrs[:reason_code] || :streak,
        reason_text: attrs[:reason_text],
        metadata: metadata
      })
      |> Repo.insert()

    {req, student, parent}
  end

  describe "build/1" do
    test "returns {:ok, email} with subject containing the student's name" do
      {req, _s, _p} = build_request(%{})
      assert {:ok, email} = ParentRequestEmail.build(req)
      assert email.subject =~ "Lia"
    end

    test "renders the student's reason text for :other" do
      {req, _s, _p} =
        build_request(%{reason_code: :other, reason_text: "I want to beat my rival"})

      assert {:ok, email} = ParentRequestEmail.build(req)
      assert email.html_body =~ "I want to beat my rival"
      assert email.text_body =~ "I want to beat my rival"
    end

    test "renders streak and weekly numbers verbatim" do
      {req, _s, _p} = build_request(%{metadata: %{"streak_days" => 3, "weekly_minutes" => 42}})
      assert {:ok, email} = ParentRequestEmail.build(req)
      assert email.text_body =~ "3-day streak"
      assert email.text_body =~ "42 min of focused practice"
    end

    test "omits the upcoming-test line when metadata has none (§8.2)" do
      {req, _s, _p} = build_request(%{metadata: %{"upcoming_test" => nil}})
      assert {:ok, email} = ParentRequestEmail.build(req)
      refute email.text_body =~ "is in"
      refute email.html_body =~ "is in"
    end

    test "renders the upcoming-test line when present" do
      {req, _s, _p} =
        build_request(%{
          metadata: %{
            "upcoming_test" => %{
              "name" => "Chem Unit 3",
              "date" => "2026-05-01",
              "days_away" => 9
            }
          }
        })

      assert {:ok, email} = ParentRequestEmail.build(req)
      assert email.text_body =~ "Chem Unit 3 is in 9 days"
    end

    test "returns {:error, :no_guardian_email} when guardian email is nil" do
      {req, _s, parent} = build_request(%{})
      # Null out the email
      import Ecto.Query

      from(u in FunSheep.Accounts.UserRole, where: u.id == ^parent.id)
      |> Repo.update_all(set: [email: nil])

      req = req |> Repo.preload([:guardian, :student], force: true)
      assert {:error, :no_guardian_email} = ParentRequestEmail.build(req)
    end

    test "HTML-escapes the student's reason text" do
      {req, _s, _p} =
        build_request(%{reason_code: :other, reason_text: "<script>alert(1)</script>"})

      assert {:ok, email} = ParentRequestEmail.build(req)
      refute email.html_body =~ "<script>alert(1)</script>"
      assert email.html_body =~ "&lt;script&gt;"
    end
  end
end
