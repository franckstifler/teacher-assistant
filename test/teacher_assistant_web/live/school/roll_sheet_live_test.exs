defmodule TeacherAssistantWeb.School.RollSheetLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.LessonNotHeld

  @monday ~D[2025-09-15]

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée F"})

    scope = school_scope(head, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    :ok = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    for name <- ["Awa", "Beti"],
        do: {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: name, sex: :f})

    [awa, beti] = for r <- Enrollment.list_roster(scope, cg), do: r.enrollment
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      scope: scope,
      cg: cg,
      tc: tc,
      p1: p1,
      awa: awa,
      beti: beti,
      path: ~p"/school/classes/#{cg.id}/roll-sheet?week=2025-09-15"
    }
  end

  defp cell(e, p), do: "#cell-#{e.id}-#{@monday}-#{p.id}"

  defp entries(ctx),
    do: Attendance.for_class_range!(ctx.cg.id, @monday, @monday, scope: ctx.scope)

  test "a surveillant types a week in", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view |> element(cell(ctx.awa, ctx.p1)) |> render_click()
    view |> element(cell(ctx.beti, ctx.p1)) |> render_click()
    view |> element(cell(ctx.beti, ctx.p1)) |> render_click()
    view |> element("#done-#{@monday}-#{ctx.p1.id}") |> render_click()

    assert view |> element("#save-week") |> render_click() =~ "Feuille enregistrée."

    by_id = Map.new(entries(ctx), &{&1.enrollment_id, &1.status})
    assert by_id == %{ctx.awa.id => :absent, ctx.beti.id => :late}
  end

  test "a cell cycles empty → A → R → empty", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)
    target = cell(ctx.awa, ctx.p1)

    assert view |> element(target) |> render() =~ ~r/>\s*<\/button>/
    assert view |> element(target) |> render_click() && has_element?(view, target, "A")
    view |> element(target) |> render_click()
    assert has_element?(view, target, "R")
    view |> element(target) |> render_click()
    refute has_element?(view, target, "R")
    refute has_element?(view, target, "A")
  end

  test "a sent-home student's cell is locked « Renvoyé »", ctx do
    {:ok, _} = TeacherAssistant.FeeControl.record_send_out(ctx.scope, ctx.beti, @monday)
    {:ok, view, _} = live(ctx.conn, ctx.path)

    assert has_element?(view, "#{cell(ctx.beti, ctx.p1)}[disabled]", "Renvoyé")
  end

  test "an app lesson is read-only and links to its roll call", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [
        {ctx.awa.id, :present},
        {ctx.beti.id, :absent}
      ])

    {:ok, view, _} = live(ctx.conn, ctx.path)

    refute has_element?(view, "button#{cell(ctx.awa, ctx.p1)}")
    refute has_element?(view, "#done-#{@monday}-#{ctx.p1.id}")

    assert has_element?(
             view,
             ~s(a[href="/school/classes/#{ctx.cg.id}/attendance/#{ctx.p1.id}?date=2025-09-15"])
           )
  end

  test "a column with A but no tick warns before saving", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)
    view |> element(cell(ctx.awa, ctx.p1)) |> render_click()

    assert has_element?(view, "#unticked-warning", "Lundi 15")
    assert has_element?(view, "#unticked-warning", "MATH")
  end

  test "« cours non assuré » saves the lesson as not held", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)
    view |> element("#not-held-#{@monday}-#{ctx.p1.id}") |> render_click()
    view |> element("#save-week") |> render_click()

    assert [%LessonNotHeld{}] = Ash.read!(LessonNotHeld, scope: ctx.scope)
    assert entries(ctx) == []
  end

  test "a teacher cannot open it", ctx do
    member =
      TeacherAssistant.TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(member.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.school.id)

    assert {:error, {_kind, %{to: "/school", flash: %{"error" => "Accès refusé."}}}} =
             live(conn, ctx.path)
  end

  test "the register page offers the sheet for a paper class only", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/school/classes/#{ctx.cg.id}/register")
    assert has_element?(view, "#roll-sheet-link")
    assert has_element?(view, "#roll-sheet-print")

    {:ok, _} = Enrollment.set_paper_roll_call(ctx.scope, ctx.cg, false)
    {:ok, view, _} = live(ctx.conn, ~p"/school/classes/#{ctx.cg.id}/register")
    refute has_element?(view, "#roll-sheet-link")
  end
end
