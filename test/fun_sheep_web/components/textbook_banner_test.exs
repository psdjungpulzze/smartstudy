defmodule FunSheepWeb.TextbookBannerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias FunSheepWeb.TextbookBanner

  @course_id "11111111-1111-1111-1111-111111111111"

  defp status(overrides \\ %{}) do
    Map.merge(
      %{
        status: :missing,
        material: nil,
        completeness_score: nil,
        notes: nil,
        candidate_count: 0
      },
      overrides
    )
  end

  describe "full_banner/1" do
    test "renders upload CTA for :missing status" do
      html = render_component(&TextbookBanner.full_banner/1, %{status: status(), course_id: @course_id})

      assert html =~ "Upload the textbook"
      assert html =~ "Upload Textbook"
    end

    test "renders partial message + coverage pct" do
      s = status(%{status: :partial, completeness_score: 0.42, notes: "Missing ch 5"})
      html = render_component(&TextbookBanner.full_banner/1, %{status: s, course_id: @course_id})

      assert html =~ "looks incomplete"
      assert html =~ "42%"
      assert html =~ "Missing ch 5"
    end

    test "renders processing tone for :processing status" do
      s = status(%{status: :processing})
      html = render_component(&TextbookBanner.full_banner/1, %{status: s, course_id: @course_id})

      assert html =~ "being processed"
    end

    test "renders navigate link when cta_navigate is set" do
      html =
        render_component(&TextbookBanner.full_banner/1, %{
          status: status(),
          course_id: @course_id,
          cta_navigate: "/courses/#{@course_id}?upload=1"
        })

      assert html =~ ~s|href="/courses/#{@course_id}?upload=1"|
    end

    test "renders nothing visible when status is :complete" do
      html =
        render_component(&TextbookBanner.full_banner/1, %{
          status: status(%{status: :complete}),
          course_id: @course_id
        })

      refute html =~ "Upload"
    end
  end

  describe "compact_badge/1" do
    test "renders short label for :missing" do
      html = render_component(&TextbookBanner.compact_badge/1, %{status: status()})
      assert html =~ "No textbook"
    end

    test "renders short label for :partial" do
      html =
        render_component(&TextbookBanner.compact_badge/1, %{status: status(%{status: :partial})})

      assert html =~ "Textbook incomplete"
    end

    test "is hidden for :complete" do
      html =
        render_component(&TextbookBanner.compact_badge/1, %{status: status(%{status: :complete})})

      refute html =~ "Textbook ready"
      assert html =~ "hidden"
    end
  end
end
