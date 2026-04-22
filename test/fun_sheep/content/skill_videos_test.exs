defmodule FunSheep.Content.SkillVideosTest do
  @moduledoc """
  Tests the `Content.list_videos_for_section/1` query used by the practice
  UI to surface remediation videos on wrong-answer events (North Star I-14).

  Honesty guard (I-16): unlinked sections return `[]`; non-video sources
  don't leak in; videos without URLs are excluded.
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Content, Courses, ContentFixtures}

  defp mk_source(course, attrs) do
    defaults = %{
      source_type: "video",
      title: "Fraction basics",
      url: "https://example.com/video",
      status: "processed",
      course_id: course.id
    }

    {:ok, source} =
      Content.create_discovered_source(Map.merge(defaults, attrs))

    source
  end

  setup do
    course = ContentFixtures.create_course()

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, section_a} =
      Courses.create_section(%{name: "Adding fractions", position: 1, chapter_id: chapter.id})

    {:ok, section_b} =
      Courses.create_section(%{name: "Subtracting fractions", position: 2, chapter_id: chapter.id})

    %{course: course, chapter: chapter, section_a: section_a, section_b: section_b}
  end

  test "returns videos linked to the requested section only", ctx do
    mine =
      mk_source(ctx.course, %{
        title: "Adding fractions 101",
        url: "https://example.com/add",
        section_id: ctx.section_a.id
      })

    _other =
      mk_source(ctx.course, %{
        title: "Subtracting fractions 101",
        url: "https://example.com/sub",
        section_id: ctx.section_b.id
      })

    results = Content.list_videos_for_section(ctx.section_a.id)
    ids = Enum.map(results, & &1.id)

    assert mine.id in ids
    assert length(ids) == 1
  end

  test "excludes non-video source types even when linked to the section", ctx do
    mk_source(ctx.course, %{
      source_type: "textbook",
      title: "Textbook chapter",
      url: "https://example.com/book",
      section_id: ctx.section_a.id
    })

    assert Content.list_videos_for_section(ctx.section_a.id) == []
  end

  test "returns [] when no videos are linked (honesty, I-16)", ctx do
    mk_source(ctx.course, %{
      title: "Course-level video",
      url: "https://example.com/course-video"
      # no section_id
    })

    assert Content.list_videos_for_section(ctx.section_a.id) == []
  end

  test "nil section_id returns []" do
    assert Content.list_videos_for_section(nil) == []
  end

  test "excludes videos without URLs", ctx do
    {:ok, _} =
      Content.create_discovered_source(%{
        source_type: "video",
        title: "Nonexistent URL",
        url: nil,
        status: "discovered",
        course_id: ctx.course.id,
        section_id: ctx.section_a.id
      })

    assert Content.list_videos_for_section(ctx.section_a.id) == []
  end
end
