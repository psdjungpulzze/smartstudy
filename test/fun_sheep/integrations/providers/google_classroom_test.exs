defmodule FunSheep.Integrations.Providers.GoogleClassroomTest do
  use ExUnit.Case, async: true

  alias FunSheep.Integrations.Providers.GoogleClassroom

  describe "service_id/0 + default_scopes/0 + supported?/0" do
    test "reports supported with google classroom scopes" do
      assert GoogleClassroom.service_id() == "google_classroom"
      assert GoogleClassroom.supported?() == true
      scopes = GoogleClassroom.default_scopes()
      assert "https://www.googleapis.com/auth/classroom.courses.readonly" in scopes
      assert "https://www.googleapis.com/auth/classroom.coursework.me.readonly" in scopes
    end
  end

  describe "normalize_course/1" do
    test "maps a Google Classroom course into Course attrs" do
      raw = %{
        "id" => "gc_course_1",
        "name" => "Algebra 1",
        "section" => "Period 3",
        "description" => "Intro to algebra",
        "descriptionHeading" => "Grade 9 Math"
      }

      attrs = GoogleClassroom.normalize_course(raw)

      assert attrs.name == "Algebra 1"
      assert attrs.subject == "Period 3"
      assert attrs.grade == "9"
      assert attrs.external_provider == "google_classroom"
      assert attrs.external_id == "gc_course_1"
      assert %DateTime{} = attrs.external_synced_at
      assert attrs.metadata["source"] == "google_classroom"
    end

    test "falls back to 'Unknown' grade when no heading is present" do
      raw = %{"id" => "gc_2", "name" => "Art", "section" => "Art Section"}
      attrs = GoogleClassroom.normalize_course(raw)
      assert attrs.grade == "Unknown"
    end
  end

  describe "normalize_assignment/3" do
    test "returns a TestSchedule attrs map when title looks test-like" do
      raw = %{
        "id" => "gc_work_1",
        "title" => "Unit 3 Quiz",
        "dueDate" => %{"year" => 2026, "month" => 5, "day" => 15}
      }

      attrs =
        GoogleClassroom.normalize_assignment(
          raw,
          "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
          "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
        )

      assert attrs.name == "Unit 3 Quiz"
      assert attrs.test_date == ~D[2026-05-15]
      assert attrs.course_id == "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
      assert attrs.user_role_id == "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
      assert attrs.scope == %{"chapter_ids" => []}
      assert attrs.external_provider == "google_classroom"
    end

    test ":skip when title is not test-like" do
      raw = %{
        "id" => "gc_work_2",
        "title" => "Read chapter 4",
        "dueDate" => %{"year" => 2026, "month" => 5, "day" => 15}
      }

      assert :skip =
               GoogleClassroom.normalize_assignment(
                 raw,
                 "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
                 "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
               )
    end

    test ":skip when the due date is missing" do
      raw = %{"id" => "gc_work_3", "title" => "Midterm Exam"}

      assert :skip =
               GoogleClassroom.normalize_assignment(
                 raw,
                 "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa",
                 "bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb"
               )
    end
  end
end
