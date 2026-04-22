defmodule FunSheepWeb.StudentLive.Shared.StudyHeatmapTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheepWeb.StudentLive.Shared.StudyHeatmap

  test "renders empty state when grid has no minutes" do
    html = render_component(&StudyHeatmap.heatmap/1, grid: %{})
    assert html =~ "No study sessions in the last four weeks yet"
  end

  test "renders cells with minute counts" do
    grid = %{
      {1, "morning"} => 45,
      {3, "afternoon"} => 20
    }

    html = render_component(&StudyHeatmap.heatmap/1, grid: grid)
    assert html =~ "45"
    assert html =~ "20"
    assert html =~ "Morning"
    assert html =~ "Mon"
  end
end
