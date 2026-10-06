defmodule TeacherAssistantWeb.School.ConductLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Discipline,
    Enrollment,
    Organization,
    Timetabling
  }

  alias TeacherAssistant.TeacherFixtures

  # The test clock is frozen at Monday 2025-09-15.
  @today ~D[2025-09-15]

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée C"})

    scope = school_scope(head, school)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    [%{enrollment: awa}, %{enrollment: bob}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    {:ok, _} = Discipline.add_sanction(scope, awa, %{type: :avertissement, date: @today})
    seq = Organization.current_sequence(scope, year, @today)

    %{
      conn: Plug.Conn.put_session(conn, :workspace_id, school.id),
      school: school,
      scope: scope,
      cg: cg,
      awa: awa,
      bob: bob,
      seq: seq,
      tc: tc,
      p1: p1
    }
  end

  defp path(ctx), do: ~p"/school/conduct?class=#{ctx.cg.id}&seq=#{ctx.seq.id}"

  test "shows each student's facts and suggestion, inputs pre-filled with it",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    awa_row = view |> element("#conduct-row-#{ctx.awa.id}") |> render()
    assert awa_row =~ "Avertissement"
    assert awa_row =~ "18"
    assert has_element?(view, "#conduct-input-#{ctx.awa.id}[value='18']")
    assert has_element?(view, "#conduct-input-#{ctx.bob.id}[value='20']")
  end

  test "an edited row is marked « ajustée »; applying the suggestions resets it",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "16"}}) |> render_change()
    assert view |> element("#conduct-row-#{ctx.awa.id}") |> render() =~ "ajustée"

    view |> element("#apply-suggestions") |> render_click()
    refute view |> element("#conduct-row-#{ctx.awa.id}") |> render() =~ "ajustée"
    assert has_element?(view, "#conduct-input-#{ctx.awa.id}[value='18']")
  end

  test "validating the class saves every row", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view
    |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "16,5", ctx.bob.id => "20"}})
    |> render_submit()

    assert render(view) =~ "2 notes de conduite enregistrées"

    [awa_row, bob_row] = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)
    assert Decimal.equal?(awa_row.current, Decimal.new("16.5"))
    assert Decimal.equal?(bob_row.current, 20)
  end

  test "a bad value names the student and saves nothing", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view
    |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "16", ctx.bob.id => "25"}})
    |> render_submit()

    assert view |> element("#conduct-error") |> render() =~ "Bob"
    assert Enum.all?(Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq), &is_nil(&1.current))
  end

  test "tapping a row shows its deductions", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))
    refute has_element?(view, "#deductions-#{ctx.awa.id}")
    view |> element("#conduct-name-#{ctx.awa.id}") |> render_click()
    assert view |> element("#deductions-#{ctx.awa.id}") |> render() =~ "Avertissement"
  end

  test "a plain teacher is sent back", %{school: school, scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/conduct")
  end

  test "chips show their points; deductions show rounded points", %{conn: conn} = ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @today, [{ctx.bob.id, :absent}])

    {:ok, view, _} = live(conn, path(ctx))

    assert view |> element("#conduct-row-#{ctx.awa.id}") |> render() =~ "Avertissement −2"

    view |> element("#conduct-name-#{ctx.bob.id}") |> render_click()
    deductions = view |> element("#deductions-#{ctx.bob.id}") |> render()
    assert deductions =~ "−0,42"
    refute deductions =~ "41666"
  end

  test "the same value written differently is not « ajustée »", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view
    |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "18.0", ctx.bob.id => "20,00"}})
    |> render_change()

    refute view |> element("#conduct-row-#{ctx.awa.id}") |> render() =~ "ajustée"
    refute view |> element("#conduct-row-#{ctx.bob.id}") |> render() =~ "ajustée"
  end

  test "a pick without a séquence does not crash", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))
    render_change(view, "pick", %{"class" => ctx.cg.id})
    assert has_element?(view, "#conduct-form")
  end
end
