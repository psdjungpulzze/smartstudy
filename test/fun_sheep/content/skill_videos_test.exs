defmodule FunSheep.Content.SkillVideosTest do
  @moduledoc """
  Tests `Content.list_videos_for_section/1` (North Star I-14, I-16).
  """

  use FunSheep.DataCase, async: true

  alias FunSheep.{Content, Courses, ContentFixtures}

  defp mk_source(course, attrs) do
    defaults = %{
      source_type: "video",
      title: "Video",
      url: "https://example.com/v",
      status: "processed",
      course_id: course.id
    }

    {:ok, s} = Content.create_discovered_source(Map.merge(defaults, attrs))
    s
  end

  setup do
    course = ContentFixtures.create_course()

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Ch 1", position: 1, course_id: course.id})

    {:ok, sec_a} =
      Courses.create_section(%{name: "A", position: 1, chapter_id: chapter.id})

    {:ok, sec_b} =
      Courses.create_section(%{name: "B", position: 2, chapter_id: chapter.id})

    %{course: course, sec_a: sec_a, sec_b: sec_b}
  end

  test "returns videos linked to the requested section only", ctx do
    mine =
      mk_source(ctx.course, %{
        title: "A video",
        url: "https://example.com/a",
        section_id: ctx.sec_a.id
      })

    _other =
      mk_source(ctx.course, %{
        title: "B video",
        url: "https://example.com/b",
        section_id: ctx.sec_b.id
      })

    results = Content.list_videos_for_section(ctx.sec_a.id)
    assert [^mine | _] = results
    assert length(results) == 1
  end

  test "excludes non-video source types", ctx do
    mk_source(ctx.course, %{
      source_type: "textbook",
      title: "Book",
      url: "https://example.com/b",
      section_id: ctx.sec_a.id
    })

    assert Content.list_videos_for_section(ctx.sec_a.id) == []
  end

  test "returns [] when no videos linked", ctx do
    mk_source(ctx.course, %{title: "No section", url: "https://example.com/no"})
    assert Content.list_videos_for_section(ctx.sec_a.id) == []
  end

  test "nil section_id returns []" do
    assert Content.list_videos_for_section(nil) == []
  end

  test "excludes videos without URLs", ctx do
    {:ok, _} =
      Content.create_discovered_source(%{
        source_type: "video",
        title: "No URL",
        url: nil,
        status: "discovered",
        course_id: ctx.course.id,
        section_id: ctx.sec_a.id
      })

    assert Content.list_videos_for_section(ctx.sec_a.id) == []
  end
end
