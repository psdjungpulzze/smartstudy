defmodule FunSheepWeb.AdminCourseSectionsLiveTest do
  @moduledoc """
  Tests for the AdminCourseSectionsLive page.

  Covers both the LiveView rendering / event handling and the underlying
  Resources context operations that the LiveView delegates to.
  """
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import FunSheep.DataCase, only: [errors_on: 1]

  alias FunSheep.{Courses, Resources}

  # ── Auth helpers ──

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: "admin-user-id",
      dev_user: %{
        "id" => "admin-user-id",
        "role" => "admin",
        "email" => "admin@example.com",
        "display_name" => "Admin User"
      }
    })
  end

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

  # ── LiveView tests ──

  describe "mount/3" do
    test "renders the course name in the page title", %{conn: conn} do
      course = create_course(%{name: "Physics 202"})
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      assert html =~ "Physics 202"
    end

    test "shows back link to /admin/courses", %{conn: conn} do
      course = create_course()
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      assert html =~ "/admin/courses"
      assert html =~ "Courses"
    end

    test "shows section list when course has chapters and sections", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      assert html =~ section.name
      assert html =~ "Chapter 1"
    end

    test "shows 'No chapters found' when course has no chapters", %{conn: conn} do
      course = create_course(%{name: "Empty Course"})
      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      assert html =~ "No chapters found"
    end

    test "shows prompt to select a section when none is selected", %{conn: conn} do
      course = create_course()
      _chapter_and_section = add_chapter_and_section(course)

      {:ok, _view, html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      assert html =~ "Select a section on the left to manage its video resources."
    end

    test "redirects non-admin users with a not-found error", %{conn: conn} do
      course = create_course()

      non_admin_conn =
        conn
        |> init_test_session(%{
          dev_user_id: "student-id",
          dev_user: %{
            "id" => "student-id",
            "role" => "student",
            "email" => "student@example.com",
            "display_name" => "Student"
          }
        })

      assert_raise FunSheepWeb.NotFoundError, fn ->
        live(non_admin_conn, ~p"/admin/courses/#{course.id}/sections")
      end
    end
  end

  describe "select_section event" do
    test "selecting a section reveals the Add Video form", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      html = render_click(view, "select_section", %{"id" => section.id})

      assert html =~ "Add Video Resource"
      assert html =~ "No videos added yet."
    end

    test "selecting a section shows videos that belong to it", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, _video} = Resources.create_video_resource(video_attrs(course, section))

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      html = render_click(view, "select_section", %{"id" => section.id})

      assert html =~ "Mitosis Explained"
      assert html =~ "youtube.com"
    end

    test "selecting a section clears any prior form error", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      # Select the section, then verify form renders with no error message
      html = render_click(view, "select_section", %{"id" => section.id})

      refute html =~ "url: must be"
    end
  end

  describe "add_video event" do
    test "adding a video with valid params shows flash and video in the list", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      # First select the section so the form is visible
      render_click(view, "select_section", %{"id" => section.id})

      html =
        render_click(view, "add_video", %{
          "title" => "Khan Academy: Cell Biology",
          "url" => "https://www.khanacademy.org/science/cell",
          "source" => "khan_academy",
          "duration_seconds" => "600"
        })

      assert html =~ "Video resource added."
      assert html =~ "Khan Academy: Cell Biology"
    end

    test "adding a video with an invalid URL shows a form error", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      render_click(view, "select_section", %{"id" => section.id})

      html =
        render_click(view, "add_video", %{
          "title" => "Bad URL Video",
          "url" => "not-a-valid-url",
          "source" => "other"
        })

      assert html =~ "url:"
    end

    test "adding a video with a blank title shows a form error", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      render_click(view, "select_section", %{"id" => section.id})

      html =
        render_click(view, "add_video", %{
          "title" => "",
          "url" => "https://www.youtube.com/watch?v=abc",
          "source" => "youtube"
        })

      assert html =~ "title:"
    end

    test "adding a video without duration_seconds still succeeds", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      render_click(view, "select_section", %{"id" => section.id})

      html =
        render_click(view, "add_video", %{
          "title" => "No Duration Video",
          "url" => "https://www.youtube.com/watch?v=noduration",
          "source" => "youtube",
          "duration_seconds" => ""
        })

      assert html =~ "Video resource added."
      assert html =~ "No Duration Video"
    end
  end

  describe "delete_video event" do
    test "deleting a video removes it from the list and shows flash", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, video} = Resources.create_video_resource(video_attrs(course, section))

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      render_click(view, "select_section", %{"id" => section.id})

      html = render_click(view, "delete_video", %{"id" => video.id})

      assert html =~ "Video resource removed."
      refute html =~ "Mitosis Explained"
    end

    test "deleting one video leaves other videos for the same section intact", %{conn: conn} do
      course = create_course()
      {_chapter, section} = add_chapter_and_section(course)

      {:ok, v1} = Resources.create_video_resource(video_attrs(course, section))

      {:ok, v2} =
        Resources.create_video_resource(
          video_attrs(course, section)
          |> Map.put(:title, "Second Video")
          |> Map.put(:url, "https://www.youtube.com/watch?v=second")
        )

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/courses/#{course.id}/sections")

      render_click(view, "select_section", %{"id" => section.id})

      html = render_click(view, "delete_video", %{"id" => v1.id})

      refute html =~ v1.title
      assert html =~ v2.title
    end
  end

  # ── Context layer tests (kept from original implementation) ──

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
