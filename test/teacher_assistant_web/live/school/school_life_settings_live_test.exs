defmodule TeacherAssistantWeb.School.SchoolLifeSettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  defp conn_for(workspace, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, workspace.id)
  end

  test "settings links to the page, which shows the defaults and the example", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#school-life-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/school-life")

    assert has_element?(
             view,
             "#school-life-form input[name='school_life[absence_alert_hours]'][value='10']"
           )

    assert has_element?(
             view,
             "#school-life-form input[name='school_life[late_as_absence_minutes]'][value='']"
           )

    assert view |> element("#conduct-example") |> render() =~ "14,5"
  end

  test "the SG saves; the example follows the form", %{workspace: ws, scope: scope} do
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    {:ok, view, _} = live(conn_for(ws, sg.current_user), ~p"/school/settings/school-life")

    view
    |> form("#school-life-form", %{school_life: %{conduct_points_per_absence_hour: "1"}})
    |> render_change()

    # 20 − 6 − 0.5 − 2
    assert view |> element("#conduct-example") |> render() =~ "11,5"

    view
    |> form("#school-life-form", %{
      school_life: %{late_as_absence_minutes: "15", absence_alert_hours: "8"}
    })
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    assert Attendance.school_life_rules(scope).late_as_absence_minutes == 15
    assert Attendance.school_life_rules(scope).absence_alert_hours == 8
  end

  test "an unchecked type is saved as not in use; none checked is refused", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/settings/school-life")

    view
    |> form("#school-life-form", %{
      school_life: %{sanction_types_in_use: ["avertissement", "blame"]}
    })
    |> render_submit()

    assert Enum.sort(Attendance.school_life_rules(scope).sanction_types_in_use) == [
             :avertissement,
             :blame
           ]

    view
    |> form("#school-life-form", %{school_life: %{sanction_types_in_use: []}})
    |> render_submit()

    assert has_element?(view, "#school-life-error")
  end

  test "a plain teacher is sent back to settings", %{workspace: ws, scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn_for(ws, teacher.current_user), ~p"/school/settings/school-life")
  end

  test "an out-of-range value shows a readable message", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/school-life")

    view
    |> form("#school-life-form", %{school_life: %{late_as_absence_minutes: "500"}})
    |> render_submit()

    error = view |> element("#school-life-error") |> render()
    assert error =~ "240"
    refute error =~ "%{max}"
  end
end
