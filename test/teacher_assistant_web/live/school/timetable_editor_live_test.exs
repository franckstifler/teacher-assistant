defmodule TeacherAssistantWeb.School.TimetableEditorLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    Timetabling,
    TeacherFixtures
  }

  setup :register_and_log_in_user

  setup %{scope: scope, actor: head} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    {:ok, ma} = Curriculum.assign_teacher(scope, a, head, %{subject: "Maths"})
    {:ok, mb} = Curriculum.assign_teacher(scope, b, head, %{subject: "Maths"})
    %{scope: scope, a: a, b: b, ma: ma, mb: mb, p1: p1, p2: p2}
  end

  test "tabs, a chip places a lesson, the hours update", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#class-tab-#{ctx.b.id}")
    assert has_element?(view, "#conflict-count", "Aucun conflit")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#chip-#{ctx.ma.id}") |> render_click()
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
    assert has_element?(view, "#hours-#{ctx.ma.id}", "1/")
  end

  test "a clash is saved, shown in red, counted, and fixed by a move", %{conn: conn} = ctx do
    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.b, %{
        day: :monday,
        period_id: ctx.p1.id,
        teaching_context_id: ctx.mb.id
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#chip-#{ctx.ma.id}") |> render_click()

    assert has_element?(view, "#cell-monday-#{ctx.p1.id}.clash-cell")
    assert has_element?(view, "#conflict-count", "1 conflit")
    assert has_element?(view, "#conflict-text", "6e R")

    view |> element("#fix-0") |> render_click()
    assert has_element?(view, "#conflict-count", "Aucun conflit")
  end

  test "clearing a cell", %{conn: conn} = ctx do
    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.a, %{
        day: :monday,
        period_id: ctx.p1.id,
        teaching_context_id: ctx.ma.id
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#clear-cell") |> render_click()
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
  end

  test "crafted events on a closed cell or another school's class write nothing",
       %{conn: conn} = ctx do
    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday),
        "default_lesson_minutes" => "50"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    render_hook(view, "select", %{"day" => "saturday", "period" => ctx.p1.id})
    render_hook(view, "place", %{"tc" => ctx.ma.id})
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:saturday, ctx.p1.id}]

    render_hook(view, "select", %{"day" => "monday", "period" => "not-a-uuid"})
    render_hook(view, "place", %{"tc" => ctx.ma.id})
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots == %{}

    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()

    {:ok, foreign} =
      Enrollment.create_class_group(other, Organization.current_academic_year(other), %{
        label: "X",
        level: "6ème"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{foreign.id}")
    refute has_element?(view, "#class-tab-#{foreign.id}")
  end

  test "a plain teacher is redirected", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/timetable")
  end

  test "the old class page sends an editor to the editor", %{conn: conn} = ctx do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/school/classes/#{ctx.a.id}/timetable")

    assert to == "/school/timetable?class=#{ctx.a.id}"
  end

  test "the grid shows lesson days only and greys Wednesday afternoon (spec J1)",
       %{conn: conn} = ctx do
    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday),
        "wednesday_afternoon_off?" => "true",
        "default_lesson_minutes" => "50"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    refute has_element?(view, "th", "Samedi")

    late =
      Enum.find(
        Attendance.list_periods(ctx.scope),
        &(&1.kind == :lesson and Time.compare(&1.start_time, ~T[13:00:00]) != :lt)
      )

    assert has_element?(view, "#cell-wednesday-#{late.id}.closed-cell")
  end

  test "the editor links to the class timetable print", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, ~s(a[href="/school/classes/#{ctx.a.id}/timetable/print"]))
  end

  test "a combined course is placed and cleared in every member class", %{conn: conn} = ctx do
    {:ok, _course} = Curriculum.combine_course(ctx.scope, [ctx.ma, ctx.mb])
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#chip-#{ctx.ma.id}", "regroupé")
    view |> element("#chip-#{ctx.ma.id}") |> render_click()

    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}].teaching_context_id ==
             ctx.ma.id

    assert Timetabling.class_timetable(ctx.scope, ctx.b).slots[{:monday, ctx.p1.id}].teaching_context_id ==
             ctx.mb.id

    assert has_element?(view, "#conflict-count", "Aucun conflit")

    view |> element("#clear-cell") |> render_click()
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
    refute Timetabling.class_timetable(ctx.scope, ctx.b).slots[{:monday, ctx.p1.id}]
  end
end
