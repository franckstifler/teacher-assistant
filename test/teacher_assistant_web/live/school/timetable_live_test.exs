defmodule TeacherAssistantWeb.School.TimetableLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Organization.create_school(head, %{name: "Lycée T"})
    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      tc: tc,
      period: period,
      head: head,
      scope: scope
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
    period: period,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    html =
      view
      |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => tc.id})
      |> render_change()

    assert html =~ "1/"

    timetable = Timetabling.class_timetable(scope, cg)
    assert timetable.slots[{:monday, period.id}].teaching_context_id == tc.id
  end

  test "admin clearing a cell removes the slot", %{
    conn: conn,
    cg: cg,
    tc: tc,
    period: period,
    scope: scope
  } do
    {:ok, _slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    view
    |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => ""})
    |> render_change()

    timetable = Timetabling.class_timetable(scope, cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
  end

  test "placing a combined assignment fills the same cell for every member class, and clearing it clears both",
       %{
         conn: conn,
         cg: cg,
         tc: tc,
         period: period,
         year: year,
         head: head,
         scope: scope
       } do
    {:ok, other_cg} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    {:ok, other_tc} = Curriculum.assign_teacher(scope, other_cg, head, %{subject: "Maths"})
    {:ok, _course} = Curriculum.combine_course(scope, [tc, other_tc])

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/timetable")

    html =
      view
      |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => tc.id})
      |> render_change()

    assert html =~ "combiné"

    timetable = Timetabling.class_timetable(scope, cg)
    other_timetable = Timetabling.class_timetable(scope, other_cg)
    assert timetable.slots[{:monday, period.id}].teaching_context_id == tc.id
    assert other_timetable.slots[{:monday, period.id}].teaching_context_id == other_tc.id

    view
    |> form("#cell-monday-#{period.id} form", %{"teaching_context_id" => ""})
    |> render_change()

    timetable = Timetabling.class_timetable(scope, cg)
    other_timetable = Timetabling.class_timetable(scope, other_cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
    refute Map.has_key?(other_timetable.slots, {:monday, period.id})
  end

  test "placing a clashing teacher flashes and creates no slot", %{
    conn: conn,
    cg: cg,
    tc: tc,
    period: period,
    year: year,
    head: head,
    scope: scope
  } do
    {:ok, other_cg} =
      Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

    {:ok, other_tc} = Curriculum.assign_teacher(scope, other_cg, head, %{subject: "Maths"})

    {:ok, _slot} =
      Timetabling.place_slot(scope, other_cg, %{
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

    timetable = Timetabling.class_timetable(scope, cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
  end

  test "a form master sees the grid read-only with no cell selects", %{
    conn: _conn,
    cg: cg,
    tc: tc,
    period: period,
    school: school,
    head: head,
    scope: scope
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, fm)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)

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

    timetable = Timetabling.class_timetable(scope, cg)
    refute Map.has_key?(timetable.slots, {:monday, period.id})
  end

  test "a non-member is redirected to /school", %{school: school, cg: cg, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

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
    {:ok, os} = Organization.create_school(other, %{name: "Autre"})
    other_scope = school_scope(other, os)

    {:ok, oy} =
      Organization.create_academic_year(os, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Enrollment.create_class_group(other_scope, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/timetable")
  end
end
