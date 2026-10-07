defmodule TeacherAssistantWeb.School.HolidaysLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Organization, TeacherFixtures}

  setup :register_and_log_in_user

  # register_and_log_in_user builds a complete school, with its active year (prefilled on creation).
  setup %{scope: scope} do
    %{year: Organization.current_academic_year(scope)}
  end

  test "settings links to the page, which lists the prefilled holidays", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#holidays-link")
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")
    assert has_element?(view, "#holidays-table", "Fête nationale")
  end

  test "adds, then deletes a holiday; a bad range shows the error", %{
    conn: conn,
    scope: scope,
    year: year
  } do
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")

    view
    |> form("#holiday-form", %{
      holiday: %{label: "Congés de Noël", start_date: "2025-12-19", end_date: "2026-01-04"}
    })
    |> render_submit()

    h = scope |> Organization.list_holidays(year) |> Enum.find(&(&1.label == "Congés de Noël"))
    assert has_element?(view, "#holiday-row-#{h.id}")

    view |> element("#delete-holiday-#{h.id}") |> render_click()
    refute has_element?(view, "#holiday-row-#{h.id}")

    view
    |> form("#holiday-form", %{
      holiday: %{label: "X", start_date: "2026-01-04", end_date: "2025-12-19"}
    })
    |> render_submit()

    assert has_element?(view, "#holiday-error")
  end

  test "Préremplir adds back a deleted national holiday", %{conn: conn, scope: scope, year: year} do
    [first | _] = Organization.list_holidays(scope, year)
    :ok = Organization.delete_holiday(scope, first)
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")
    view |> element("#prefill-holidays") |> render_click()
    assert length(Organization.list_holidays(scope, year)) == 7
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn, ~p"/school/settings/holidays")
  end

  test "edits a holiday in place", %{conn: conn, scope: scope, year: year} do
    h = scope |> Organization.list_holidays(year) |> Enum.find(&(&1.label == "Fête nationale"))
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")
    view |> element("#edit-holiday-#{h.id}") |> render_click()

    view
    |> form("#holiday-form", %{
      holiday: %{label: "Fête nationale (pont)", start_date: "2026-05-20", end_date: "2026-05-22"}
    })
    |> render_submit()

    updated = scope |> Organization.list_holidays(year) |> Enum.find(&(&1.id == h.id))
    assert updated.label == "Fête nationale (pont)"
    assert updated.end_date == ~D[2026-05-22]
    assert length(Organization.list_holidays(scope, year)) == 7
  end

  test "a year without holidays says so", %{conn: conn, scope: scope, year: year} do
    for h <- Organization.list_holidays(scope, year),
        do: :ok = Organization.delete_holiday(scope, h)

    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")
    assert has_element?(view, "#holidays-empty")
    refute has_element?(view, "#holidays-table")
  end
end
