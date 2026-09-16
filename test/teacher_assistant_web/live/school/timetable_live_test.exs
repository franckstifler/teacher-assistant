defmodule TeacherAssistantWeb.School.TimetableLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée T"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})

    :ok = Timetables.build_default_periods(school)
    period = Timetables.list_periods(school) |> Enum.find(&(&1.kind == :lesson))

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      tc: tc,
      period: period,
      head: head
    }
  end

  test "admin loads the grid with period rows and day headers", %{
    conn: conn,
    cg: cg,
    period: period
  } do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    assert html =~ period.label
    assert html =~ "Lundi"
    assert html =~ "Samedi"
    assert html =~ "Maths"
  end

  test "admin selecting an assignment in a cell persists the slot and updates the tally", %{
    conn: conn,
    cg: cg,
    tc: tc,
    period: period
  } do
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    html =
      view
      |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => tc.id})
      |> render_change()

    assert html =~ "1/"

    timetable = Timetables.class_timetable(cg)
    assert timetable.slots[{:monday, period.id}].teaching_context_id == tc.id
  end

  test "admin clearing a cell removes the slot", %{conn: conn, cg: cg, tc: tc, period: period} do
    {:ok, _slot} =
      Timetables.place_slot(cg, %{day: :monday, period_id: period.id, teaching_context_id: tc.id})

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    view
    |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => ""})
    |> render_change()

    timetable = Timetables.class_timetable(cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
  end

  test "placing a clashing teacher flashes and creates no slot", %{
    conn: conn,
    cg: cg,
    tc: tc,
    period: period,
    school: school,
    year: year,
    head: head
  } do
    {:ok, other_cg} =
      Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})

    {:ok, other_tc} = Assignments.assign(other_cg, head, %{subject: "Maths"})

    {:ok, _slot} =
      Timetables.place_slot(other_cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: other_tc.id
      })

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    html =
      view
      |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => tc.id})
      |> render_change()

    assert html =~ "a déjà cours dans"

    timetable = Timetables.class_timetable(cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
  end

  test "a form master sees the grid read-only with no cell selects", %{
    conn: _conn,
    cg: cg,
    tc: tc,
    period: period,
    school: school,
    head: head
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, fm.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    refute html =~ "<select"

    # Forged place event should be rejected server-side.
    view
    |> render_hook("place", %{
      "day" => "monday",
      "period_id" => period.id,
      "teaching_context_id" => tc.id
    })

    timetable = Timetables.class_timetable(cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
  end

  test "a non-member is redirected to /school", %{school: school, cg: cg, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/timetable")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, os} = Schools.create_school(other, %{name: "Autre"})

    {:ok, oy} =
      Academics.create_academic_year(os, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Academics.create_class_group(os, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/timetable")
  end
end
