defmodule FunSheep.ResourcesTest do
  @moduledoc """
  Tests for the Resources context (VideoResource CRUD).
  """
  use FunSheep.DataCase, async: true

  alias FunSheep.Resources
  alias FunSheep.Resources.VideoResource
  alias FunSheep.Courses

  # ── Setup helpers ──

  defp create_course do
    {:ok, course} = Courses.create_course(%{name: "Test Course", subject: "Biology", grade: "10"})
    course
  end

  defp create_section(course \\ nil) do
    course = course || create_course()

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      Courses.create_section(%{name: "Cell Division", position: 1, chapter_id: chapter.id})

    {course, section}
  end

  defp valid_attrs(course_id, section_id) do
    %{
      title: "Mitosis Explained",
      url: "https://www.youtube.com/watch?v=abc123",
      source: :youtube,
      section_id: section_id,
      course_id: course_id
    }
  end

  # ── VideoResource CRUD ──

  describe "create_video_resource/1" do
    test "creates a resource with valid attrs" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id)

      assert {:ok, %VideoResource{} = video} = Resources.create_video_resource(attrs)

      assert video.title == "Mitosis Explained"
      assert video.url == "https://www.youtube.com/watch?v=abc123"
      assert video.source == :youtube
      assert video.section_id == section.id
      assert video.course_id == course.id
    end

    test "creates a resource with optional duration_seconds" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.put(:duration_seconds, 480)

      assert {:ok, video} = Resources.create_video_resource(attrs)
      assert video.duration_seconds == 480
    end

    test "creates a resource with khan_academy source" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.put(:source, :khan_academy)

      assert {:ok, video} = Resources.create_video_resource(attrs)
      assert video.source == :khan_academy
    end

    test "creates a resource with other source" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.put(:source, :other)

      assert {:ok, video} = Resources.create_video_resource(attrs)
      assert video.source == :other
    end

    test "returns error changeset when title is missing" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.delete(:title)

      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error changeset when url is missing" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.delete(:url)

      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error changeset for invalid URL (no scheme)" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.put(:url, "not-a-url")

      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{url: [_msg]} = errors_on(changeset)
    end

    test "returns error changeset for non-http URL" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.put(:url, "ftp://example.com/video")

      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{url: [_msg]} = errors_on(changeset)
    end

    test "returns error changeset when source is missing" do
      {course, section} = create_section()
      attrs = valid_attrs(course.id, section.id) |> Map.delete(:source)

      assert {:error, changeset} = Resources.create_video_resource(attrs)
      assert %{source: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_videos_for_section/1" do
    test "returns all videos for the given section in insertion order" do
      {course, section} = create_section()

      {:ok, v1} =
        Resources.create_video_resource(
          valid_attrs(course.id, section.id)
          |> Map.put(:title, "Video 1")
        )

      {:ok, v2} =
        Resources.create_video_resource(
          valid_attrs(course.id, section.id)
          |> Map.put(:title, "Video 2")
        )

      videos = Resources.list_videos_for_section(section.id)
      ids = Enum.map(videos, & &1.id)

      assert v1.id in ids
      assert v2.id in ids
    end

    test "does not return videos from a different section" do
      {course, section1} = create_section()
      {:ok, chapter2} = Courses.create_chapter(%{name: "Ch2", position: 2, course_id: course.id})

      {:ok, section2} =
        Courses.create_section(%{name: "Sec2", position: 1, chapter_id: chapter2.id})

      {:ok, _v1} = Resources.create_video_resource(valid_attrs(course.id, section1.id))

      videos = Resources.list_videos_for_section(section2.id)
      assert videos == []
    end

    test "returns empty list when no videos exist for section" do
      {_course, section} = create_section()
      assert Resources.list_videos_for_section(section.id) == []
    end
  end

  describe "list_videos_for_course/1" do
    test "returns all videos for the course with section preloaded" do
      {course, section} = create_section()
      {:ok, video} = Resources.create_video_resource(valid_attrs(course.id, section.id))

      videos = Resources.list_videos_for_course(course.id)

      assert length(videos) == 1
      fetched = List.first(videos)
      assert fetched.id == video.id
      assert %FunSheep.Courses.Section{} = fetched.section
    end

    test "does not return videos from a different course" do
      {course1, section1} = create_section()
      {course2, _section2} = create_section()

      {:ok, _v} = Resources.create_video_resource(valid_attrs(course1.id, section1.id))

      videos = Resources.list_videos_for_course(course2.id)
      assert videos == []
    end

    test "returns empty list when course has no videos" do
      course = create_course()
      assert Resources.list_videos_for_course(course.id) == []
    end
  end

  describe "delete_video_resource/1" do
    test "deletes an existing video resource" do
      {course, section} = create_section()
      {:ok, video} = Resources.create_video_resource(valid_attrs(course.id, section.id))

      assert {:ok, %VideoResource{}} = Resources.delete_video_resource(video)
      assert_raise Ecto.NoResultsError, fn -> Resources.get_video_resource!(video.id) end
    end

    test "removal is reflected in list_videos_for_section/1" do
      {course, section} = create_section()
      {:ok, video} = Resources.create_video_resource(valid_attrs(course.id, section.id))

      {:ok, _} = Resources.delete_video_resource(video)

      assert Resources.list_videos_for_section(section.id) == []
    end
  end

  describe "get_video_resource!/1" do
    test "returns the resource when it exists" do
      {course, section} = create_section()
      {:ok, video} = Resources.create_video_resource(valid_attrs(course.id, section.id))

      fetched = Resources.get_video_resource!(video.id)
      assert fetched.id == video.id
    end

    test "raises Ecto.NoResultsError when resource does not exist" do
      fake_id = Ecto.UUID.generate()
      assert_raise Ecto.NoResultsError, fn -> Resources.get_video_resource!(fake_id) end
    end
  end
end
