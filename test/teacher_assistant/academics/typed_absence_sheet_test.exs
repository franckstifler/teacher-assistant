defmodule TeacherAssistant.Academics.TypedAbsenceSheetTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    Scope,
    TeacherFixtures,
    Timetabling
  }

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)
    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    :ok = Organization.build_default_calendar(scope, year)
    [t1 | _] = Organization.list_terms(scope, year)
    [s1, s2 | _] = Enum.sort_by(t1.sequences, & &1.position_in_term)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: awa}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    {:ok, _} = Attendance.record_period(scope, cg, p1, tc, ~D[2025-09-08], [{awa.id, :absent}])
    {:ok, cg} = Enrollment.set_absence_hours_source(scope, cg, :typed_per_sequence)

    %{scope: scope, ws: ws, year: year, t1: t1, s1: s1, s2: s2, cg: cg, awa: awa}
  end

  defp app_hours(ctx),
    do:
      Attendance.class_conduct(ctx.scope, ctx.cg, {:sequence, ctx.s1})[ctx.awa.id].unjustified_hours

  test "sheet pre-fills from the roll call when nothing typed", ctx do
    assert [%{hours: hours, prefilled?: true, app_hours: app}] =
             Attendance.typed_absence_sheet(ctx.scope, ctx.cg, {:sequence, ctx.s1})

    assert Decimal.gt?(app, 0)
    assert Decimal.equal?(hours, app_hours(ctx))
  end

  test "sheet shows the saved figure unprefilled", ctx do
    :ok =
      Attendance.save_typed_absences(ctx.scope, ctx.cg, {:sequence, ctx.s1}, %{ctx.awa.id => "4"})

    assert [%{hours: hours, prefilled?: false}] =
             Attendance.typed_absence_sheet(ctx.scope, ctx.cg, {:sequence, ctx.s1})

    assert Decimal.equal?(hours, 4)
  end

  test "per_term sheet pre-fills the sum of séquence records", ctx do
    :ok =
      Attendance.save_typed_absences(ctx.scope, ctx.cg, {:sequence, ctx.s1}, %{ctx.awa.id => "2"})

    :ok =
      Attendance.save_typed_absences(ctx.scope, ctx.cg, {:sequence, ctx.s2}, %{ctx.awa.id => "3"})

    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, :typed_per_term)

    assert [%{hours: hours, prefilled?: true}] =
             Attendance.typed_absence_sheet(ctx.scope, cg, {:trimester, ctx.t1})

    assert Decimal.equal?(hours, 5)
  end

  test "saves and clears", ctx do
    period = {:sequence, ctx.s1}
    :ok = Attendance.save_typed_absences(ctx.scope, ctx.cg, period, %{ctx.awa.id => "4"})
    assert Attendance.bulletin_conduct(ctx.scope, ctx.cg, period)[ctx.awa.id].recorded?

    :ok = Attendance.save_typed_absences(ctx.scope, ctx.cg, period, %{ctx.awa.id => ""})
    refute Attendance.bulletin_conduct(ctx.scope, ctx.cg, period)[ctx.awa.id].recorded?
  end

  test "parses a decimal comma", ctx do
    period = {:sequence, ctx.s1}
    :ok = Attendance.save_typed_absences(ctx.scope, ctx.cg, period, %{ctx.awa.id => " 2,5 "})

    assert Decimal.equal?(
             Attendance.bulletin_conduct(ctx.scope, ctx.cg, period)[ctx.awa.id].unjustified_hours,
             Decimal.new("2.5")
           )
  end

  test "refuses invalid rows and saves nothing", ctx do
    period = {:sequence, ctx.s1}

    for bad <- ["abc", "-1", "2h", "NaN", "inf"] do
      assert {:error, %{} = errors} =
               Attendance.save_typed_absences(ctx.scope, ctx.cg, period, %{ctx.awa.id => bad})

      assert errors == %{ctx.awa.id => :invalid}
    end

    refute Attendance.bulletin_conduct(ctx.scope, ctx.cg, period)[ctx.awa.id].recorded?
  end

  test "refuses enrollments outside the class", ctx do
    {:ok, other} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    {:ok, _} = Enrollment.add_student(ctx.scope, other, %{full_name: "Zoé", sex: :f})
    [%{enrollment: zoe}] = Enrollment.list_roster(ctx.scope, other)

    assert {:error, :not_in_class} =
             Attendance.save_typed_absences(ctx.scope, ctx.cg, {:sequence, ctx.s1}, %{
               zoe.id => "3"
             })
  end

  test "a closed year refuses the save instead of crashing", ctx do
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    {:ok, ws} = Organization.set_modules(op, ctx.ws, [:notes, :discipline])
    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, :roll_call)
    TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_workspace: ws}

    assert {:error, _} =
             Attendance.save_typed_absences(scope, cg, {:sequence, ctx.s1}, %{ctx.awa.id => ""})
  end

  test "stores typed_per_sequence when the school lacks appel", ctx do
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    {:ok, ws} = Organization.set_modules(op, ctx.ws, [:notes, :discipline])
    scope = %{ctx.scope | current_workspace: ws}
    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, :roll_call)

    fm = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, cg} = Enrollment.set_form_master(ctx.scope, cg, fm.current_user.id)
    fm = %{fm | current_workspace: ws, current_academic_year: ctx.year}

    assert [%{app_hours: nil, hours: nil}] =
             Attendance.typed_absence_sheet(fm, cg, {:sequence, ctx.s1})

    :ok = Attendance.save_typed_absences(fm, cg, {:sequence, ctx.s1}, %{ctx.awa.id => "1"})
    {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, cg.id)
    assert cg.absence_hours_source == :typed_per_sequence
  end
end
