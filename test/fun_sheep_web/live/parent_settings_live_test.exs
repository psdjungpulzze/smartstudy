defmodule FunSheepWeb.ParentSettingsLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

  defp user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :parent,
      email: "p_#{System.unique_integer([:positive])}@t.com",
      display_name: "P"
    }

    {:ok, u} = Accounts.create_user_role(Map.merge(defaults, attrs))
    u
  end

  defp auth(conn, u) do
    conn
    |> init_test_session(%{
      dev_user_id: u.interactor_user_id,
      dev_user: %{
        "id" => u.interactor_user_id,
        "role" => to_string(u.role),
        "email" => u.email,
        "display_name" => u.display_name,
        "interactor_user_id" => u.interactor_user_id
      }
    })
  end

  test "saves digest + alert preferences", %{conn: conn} do
    parent = user_role(%{})
    conn = auth(conn, parent)

    {:ok, view, html} = live(conn, ~p"/parent/settings")
    assert html =~ "Notification settings"

    render_submit(view, "save_settings", %{
      "digest_frequency" => "off",
      "alerts_skipped_days" => "on",
      "alerts_readiness_drop" => "on",
      "alerts_goal_achieved" => "on"
    })

    updated = Accounts.get_user_role!(parent.id)
    assert updated.digest_frequency == :off
    assert updated.alerts_skipped_days
    assert updated.alerts_readiness_drop
    assert updated.alerts_goal_achieved
  end
end
