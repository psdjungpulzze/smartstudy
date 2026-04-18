defmodule FunSheep.CoursesTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Courses
  alias FunSheep.Courses.{Course, Chapter, Section}
  alias FunSheep.Geo

  defp create_school(_context \\ %{}) do
    {:ok, country} = Geo.create_country(%{name: "US", code: "US"})
    {:ok, state} = Geo.create_state(%{name: "California", country_id: country.id})
    {:ok, district} = Geo.create_district(%{name: "LA Unified", state_id: state.id})
    {:ok, school} = Geo.create_school(%{name: "Test High School", district_id: district.id})
    school
  end

  defp create_course(attrs \\ %{}) do
    defaults = %{name: "Test Course", subject: "Math", grade: "10"}
    {:ok, course} = Courses.create_course(Map.merge(defaults, attrs))
    course
  end

  describe "search_courses/1" do
    test "searches by subject (ilike)" do
      create_course(%{name: "Algebra 1", subject: "Mathematics"})
      create_course(%{name: "Biology", subject: "Science"})

      results = Courses.search_courses(%{"subject" => "math"})
      assert length(results) == 1
      assert hd(results).subject == "Mathematics"
    end

    test "searches by name (ilike)" do
      create_course(%{name: "AP Calculus", subject: "Math"})
      create_course(%{name: "Biology", subject: "Science"})

      results = Courses.search_courses(%{"subject" => "calculus"})
      assert length(results) == 1
      assert hd(results).name == "AP Calculus"
    end

    test "filters by grade" do
      create_course(%{name: "Math 10", grade: "10"})
      create_course(%{name: "Math 11", grade: "11"})

      results = Courses.search_courses(%{"grade" => "10"})
      assert length(results) == 1
      assert hd(results).grade == "10"
    end

    test "filters by school_id" do
      school = create_school()
      create_course(%{name: "With School", school_id: school.id})
      create_course(%{name: "No School"})

      results = Courses.search_courses(%{"school_id" => school.id})
      assert length(results) == 1
      assert hd(results).name == "With School"
    end

    test "returns all courses with empty filters" do
      create_course(%{name: "Course A"})
      create_course(%{name: "Course B"})

      results = Courses.search_courses(%{})
      assert length(results) == 2
    end

    test "preloads school association" do
      school = create_school()
      create_course(%{name: "With School", school_id: school.id})

      [result] = Courses.search_courses(%{"subject" => "Math"})
      assert result.school.name == "Test High School"
    end
  end

  describe "create_course/1" do
    test "creates with valid attrs" do
      assert {:ok, %Course{} = course} =
               Courses.create_course(%{name: "Algebra", subject: "Math", grade: "9"})

      assert course.name == "Algebra"
      assert course.subject == "Math"
      assert course.grade == "9"
    end

    test "fails without required fields" do
      assert {:error, changeset} = Courses.create_course(%{})
      assert %{name: _, subject: _, grade: _} = errors_on(changeset)
    end
  end

  describe "update_course/2" do
    test "updates with valid attrs" do
      course = create_course()
      assert {:ok, updated} = Courses.update_course(course, %{name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "delete_course/1" do
    test "deletes the course" do
      course = create_course()
      assert {:ok, _} = Courses.delete_course(course)
      assert_raise Ecto.NoResultsError, fn -> Courses.get_course!(course.id) end
    end
  end

  describe "chapter CRUD" do
    test "create_chapter/1 with valid attrs" do
      course = create_course()

      assert {:ok, %Chapter{} = chapter} =
               Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

      assert chapter.name == "Chapter 1"
      assert chapter.position == 1
    end

    test "create_chapter/1 fails without required fields" do
      assert {:error, changeset} = Courses.create_chapter(%{})
      assert %{name: _, position: _, course_id: _} = errors_on(changeset)
    end

    test "update_chapter/2" do
      course = create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

      assert {:ok, updated} = Courses.update_chapter(chapter, %{name: "Updated Chapter"})
      assert updated.name == "Updated Chapter"
    end

    test "delete_chapter/1" do
      course = create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

      assert {:ok, _} = Courses.delete_chapter(chapter)
      assert_raise Ecto.NoResultsError, fn -> Courses.get_chapter!(chapter.id) end
    end
  end

  describe "reorder_chapters/2" do
    test "updates chapter positions" do
      course = create_course()
      {:ok, ch1} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})
      {:ok, ch2} = Courses.create_chapter(%{name: "Ch 2", position: 2, course_id: course.id})
      {:ok, ch3} = Courses.create_chapter(%{name: "Ch 3", position: 3, course_id: course.id})

      # Reverse order
      assert {:ok, _} = Courses.reorder_chapters(course.id, [ch3.id, ch2.id, ch1.id])

      chapters = Courses.list_chapters_by_course(course.id)
      assert Enum.map(chapters, & &1.name) == ["Ch 3", "Ch 2", "Ch 1"]
    end
  end

  describe "section CRUD" do
    setup do
      course = create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})
      %{course: course, chapter: chapter}
    end

    test "create_section/1 with valid attrs", %{chapter: chapter} do
      assert {:ok, %Section{} = section} =
               Courses.create_section(%{name: "Section 1", position: 1, chapter_id: chapter.id})

      assert section.name == "Section 1"
    end

    test "create_section/1 fails without required fields" do
      assert {:error, changeset} = Courses.create_section(%{})
      assert %{name: _, position: _, chapter_id: _} = errors_on(changeset)
    end

    test "update_section/2", %{chapter: chapter} do
      {:ok, section} =
        Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})

      assert {:ok, updated} = Courses.update_section(section, %{name: "Updated Section"})
      assert updated.name == "Updated Section"
    end

    test "delete_section/1", %{chapter: chapter} do
      {:ok, section} =
        Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})

      assert {:ok, _} = Courses.delete_section(section)
      assert_raise Ecto.NoResultsError, fn -> Courses.get_section!(section.id) end
    end
  end

  describe "reorder_sections/2" do
    test "updates section positions" do
      course = create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})
      {:ok, s1} = Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})
      {:ok, s2} = Courses.create_section(%{name: "Sec 2", position: 2, chapter_id: chapter.id})

      assert {:ok, _} = Courses.reorder_sections(chapter.id, [s2.id, s1.id])

      sections = Courses.list_sections_by_chapter(chapter.id)
      assert Enum.map(sections, & &1.name) == ["Sec 2", "Sec 1"]
    end
  end

  describe "get_course_with_chapters!/1" do
    test "preloads chapters with sections ordered by position" do
      course = create_course()
      {:ok, _ch2} = Courses.create_chapter(%{name: "Ch 2", position: 2, course_id: course.id})
      {:ok, ch1} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})
      {:ok, _s2} = Courses.create_section(%{name: "Sec 2", position: 2, chapter_id: ch1.id})
      {:ok, _s1} = Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: ch1.id})

      loaded = Courses.get_course_with_chapters!(course.id)

      assert length(loaded.chapters) == 2
      assert hd(loaded.chapters).name == "Ch 1"
      assert Enum.at(loaded.chapters, 1).name == "Ch 2"

      first_chapter = hd(loaded.chapters)
      assert length(first_chapter.sections) == 2
      assert hd(first_chapter.sections).name == "Sec 1"
    end

    test "raises for nonexistent course" do
      assert_raise Ecto.NoResultsError, fn ->
        Courses.get_course_with_chapters!(Ecto.UUID.generate())
      end
    end
  end

  describe "next_chapter_position/1" do
    test "returns 1 for course with no chapters" do
      course = create_course()
      assert Courses.next_chapter_position(course.id) == 1
    end

    test "returns max + 1" do
      course = create_course()
      Courses.create_chapter(%{name: "Ch 1", position: 3, course_id: course.id})
      assert Courses.next_chapter_position(course.id) == 4
    end
  end

  describe "next_section_position/1" do
    test "returns 1 for chapter with no sections" do
      course = create_course()
      {:ok, chapter} = Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})
      assert Courses.next_section_position(chapter.id) == 1
    end
  end
end
