defmodule FunSheep.Integrations.Providers.ParentSquareTest do
  use ExUnit.Case, async: true

  alias FunSheep.Integrations.Providers.ParentSquare

  test "reports unsupported" do
    assert ParentSquare.supported?() == false
    assert ParentSquare.service_id() == "parentsquare"
    assert ParentSquare.default_scopes() == []
  end

  test "list_courses / list_assignments refuse with :not_supported" do
    assert {:error, :not_supported} = ParentSquare.list_courses("token", [])
    assert {:error, :not_supported} = ParentSquare.list_assignments("token", "course_1", [])
  end

  test "normalize_assignment always returns :skip" do
    assert :skip = ParentSquare.normalize_assignment(%{}, "course-id", "user-id")
  end
end
