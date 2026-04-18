defmodule StudySmartWeb.PageControllerTest do
  use StudySmartWeb.ConnCase

  test "GET / shows login page when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome back"
  end

  test "GET / redirects to dashboard when authenticated as student", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{
        current_user: %{
          "id" => "usr_test",
          "role" => "student",
          "email" => "test@test.com",
          "display_name" => "Test"
        }
      })
      |> get(~p"/")

    assert redirected_to(conn) == "/dashboard"
  end
end
