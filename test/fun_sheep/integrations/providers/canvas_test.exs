defmodule FunSheep.Integrations.Providers.CanvasTest do
  use ExUnit.Case, async: true

  alias FunSheep.Integrations.Providers.Canvas

  describe "service_id/0 + default_scopes/0 + supported?/0" do
    test "reports supported with canvas-shaped scopes" do
      assert Canvas.service_id() == "canvas"
      assert Canvas.supported?() == true

      scopes = Canvas.default_scopes()
      assert "url:GET|/api/v1/courses" in scopes
    end
  end

  describe "normalize_course/1" do
    test "maps a Canvas course payload into Course attrs" do
      raw = %{
        "id" => 42,
        "name" => "English 10",
        "course_code" => "ENG10",
        "enrollment_term_id" => 7
      }

      attrs = Canvas.normalize_course(raw)

      assert attrs.name == "English 10"
      assert attrs.subject == "ENG10"
      assert attrs.grade == "Unknown"
      assert attrs.external_provider == "canvas"
      assert attrs.external_id == "42"
      assert attrs.metadata["course_code"] == "ENG10"
      assert %DateTime{} = attrs.external_synced_at
    end
  end

  describe "normalize_assignment/3" do
    test "returns a schedule attrs map when due_at is in the future" do
      future = DateTime.utc_now() |> DateTime.add(7 * 86_400, :second)
      due_at = DateTime.to_iso8601(future)

      raw = %{"id" => 777, "name" => "Final Exam", "due_at" => due_at}

      attrs =
        Canvas.normalize_assignment(
          raw,
          "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
          "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
        )

      assert attrs.name == "Final Exam"
      assert attrs.external_id == "777"
      assert attrs.external_provider == "canvas"
      assert Date.compare(attrs.test_date, Date.utc_today()) != :lt
    end

    test ":skip when due_at is nil or missing" do
      assert :skip =
               Canvas.normalize_assignment(
                 %{"id" => 1, "name" => "x"},
                 "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
                 "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
               )
    end

    test ":skip when due_at is in the past" do
      past = DateTime.utc_now() |> DateTime.add(-30 * 86_400, :second)

      raw = %{"id" => 8, "name" => "old", "due_at" => DateTime.to_iso8601(past)}

      assert :skip =
               Canvas.normalize_assignment(
                 raw,
                 "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
                 "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
               )
    end
  end

  describe "list_courses/2" do
    test "returns an error when no canvas host is provided" do
      assert {:error, msg} = Canvas.list_courses("token", [])
      assert msg =~ "Canvas requires an institution host"
    end
  end
end
