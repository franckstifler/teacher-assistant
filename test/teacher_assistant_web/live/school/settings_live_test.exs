defmodule TeacherAssistantWeb.School.SettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Ancien Nom"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school}
  end

  test "head renames the school", %{conn: conn, school: school} do
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#school-settings")
    view |> form("#school-settings", %{"school" => %{"name" => "Nouveau Nom"}}) |> render_submit()

    assert TeacherAssistant.Academics.get_personal_workspace(school.id)
           |> elem(1)
           |> Map.get(:name) ==
             "Nouveau Nom"
  end

  test "head creates and activates an academic year", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    assert render(view) =~ "2025-2026"
  end

  test "activating a year deactivates the previous one", %{conn: conn, school: school} do
    alias TeacherAssistant.Academics

    {:ok, y1} =
      Academics.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    {:ok, y2} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: false
      })

    {:ok, view, _} = live(conn, ~p"/school/settings")
    view |> element("#year-activate-#{y2.id}") |> render_click()

    assert Academics.current_academic_year(school).id == y2.id
    assert {:ok, %{active: false}} = Academics.get_academic_year(y1.id)
  end

  test "a plain teacher member cannot create years (forged event)", %{
    conn: _conn,
    school: school,
    actor: head
  } do
    alias TeacherAssistant.Academics

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/settings")
    refute has_element?(view, "#year-form")

    render_hook(view, "create_year", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })

    assert Academics.list_academic_years(school) == []
  end

  test "additional academic years created via form are inactive; only first is active", %{
    conn: conn,
    school: school
  } do
    alias TeacherAssistant.Academics

    # Create first year directly with active: true
    {:ok, _y1} =
      Academics.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    {:ok, view, _} = live(conn, ~p"/school/settings")

    # Submit form to create second year
    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    # First year must still be active
    assert Academics.current_academic_year(school).name == "2024-2025"

    # Second year must exist and be inactive
    years = Academics.list_academic_years(school)
    y2 = Enum.find(years, &(&1.name == "2025-2026"))
    assert y2 != nil
    assert y2.active == false
  end
end
