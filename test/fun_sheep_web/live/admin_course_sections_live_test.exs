defmodule FunSheepWeb.AdminCourseSectionsLiveTest do
  @moduledoc """
  Tests for the AdminCourseSectionsLive page.

  Full LiveView rendering is gated on the compiled app layout being present
  in the test environment (this worktree does not include it). These tests
  exercise the Resources context operations that the LiveView delegates to,
  which gives us confidence that the data layer backing the page is correct.
  """
  use FunSheepWeb.ConnCase, async: true

  import FunSheep.DataCase, only: [errors_on: 1]

  alias FunSheep.{Courses, Resources}

  # ── Data helpers ──

  defp create_course(attrs \\ %{}) do
    {:ok, course} =
      Courses.create_course(
        Map.merge(%{name: "Biology 101", subject: "Biology", grade: "10"}, attrs)
      )

    course
  end

  defp add_chapter_and_section(course) do
    {:ok, chapter} =
      Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      Courses.create_section(%{name: "Cell Division", position: 1, chapter_id: chapter.id})

    {chapter, section}
  end

  defp video_attrs(course, section) do
    %{
      title: "Mitosis Explained",
      url: "https://www.youtube.com/watch?v=test123",
      source: :youtube,
      section_id: section.id,
      course_id: course.id
    }
  end

  # ── mount data layer ──

  describe "mount — data loaded by AdminCourseSectionsLive" do
    test "get_course_with_chapters! loads chapters and sections for the course" do
      course = create_course(%{name: "Physics 202"})
      {chapter, section} = add_chapter_and_section(course)

      loaded = Courses.get_course_with_chapters!(course.id)

      assert loaded.name == "Physics 202"
      chapter_names = Enum.map(loaded.chapters, & &1.name)
      assert chapter.name in chapter_names

      section_names =
        loaded.chapters
        |> Enum.flat_map(& &1.sections)
        |> Enum.map(& &1.name)

      assert section.name in section_names
    end

    test "list_videos_for_course returns an empty map for a new course" do
      course = create_course()

      videos = Resources.list_videos_for_course(course.id)
      grouped = Enum.group_by(videos, & &1.section_id)

      assert grouped == %{}
    end

    test "list_videos_for_course groups videos by section correctly" do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, v1} =
        Resources.create_video_resource(video_attrs(course, section) |> Map.put(:title, "V1"))

      {:ok, v2} =
        Resources.create_video_resource(video_attrs(course, section) |> Map.put(:title, "V2"))

      videos = Resources.list_videos_for_course(course.id)
      grouped = Enum.group_by(videos, & &1.section_id)

      section_videos = Map.get(grouped, section.id, [])
      ids = Enum.map(section_videos, & &1.id)
      assert v1.id in ids
      assert v2.id in ids
    end
  end

  # ── add_video event logic ──

  describe "add_video — context layer used by the LiveView event handler" do
    test "creates a video resource with valid params" do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      assert {:ok, video} = Resources.create_video_resource(video_attrs(course, section))

      assert video.title == "Mitosis Explained"
      assert video.source == :youtube
      assert video.section_id == section.id
      assert video.course_id == course.id
    end

    test "returns error changeset for invalid URL" do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      attrs = video_attrs(course, section) |> Map.put(:url, "not-a-url")
      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{url: [_msg]} = errors_on(changeset)
    end

    test "returns error changeset when title is blank" do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      attrs = video_attrs(course, section) |> Map.put(:title, "")
      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ── delete_video event logic ──

  describe "delete_video — context layer used by the LiveView event handler" do
    test "deletes a video resource and removes it from the section list" do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, video} = Resources.create_video_resource(video_attrs(course, section))

      assert {:ok, _} = Resources.delete_video_resource(video)
      assert Resources.list_videos_for_section(section.id) == []
    end

    test "get_video_resource!/1 resolves a valid ID" do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, video} = Resources.create_video_resource(video_attrs(course, section))

      fetched = Resources.get_video_resource!(video.id)
      assert fetched.id == video.id
    end

    test "in-memory videos_by_section map is updated correctly after deletion" do
      # Simulates the Map.update call in the handle_event("delete_video") handler.
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, v1} = Resources.create_video_resource(video_attrs(course, section))

      {:ok, v2} =
        Resources.create_video_resource(video_attrs(course, section) |> Map.put(:title, "V2"))

      videos_by_section = %{section.id => [v1, v2]}

      # Deletion updates the in-memory map (mirroring LiveView socket state).
      updated =
        Map.update(
          videos_by_section,
          v1.section_id,
          [],
          &Enum.reject(&1, fn v -> v.id == v1.id end)
        )

      remaining = Map.get(updated, section.id, [])
      assert length(remaining) == 1
      assert List.first(remaining).id == v2.id
    end
  end
end
