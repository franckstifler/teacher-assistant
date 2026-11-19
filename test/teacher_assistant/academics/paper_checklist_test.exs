defmodule TeacherAssistant.Academics.PaperChecklistTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    ReportCards,
    TeacherFixtures,
    Timetabling
  }

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)
    # Re-read, so the scope knows the school is verified (saving a sheet needs it).
    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    _ = Organization.build_default_calendar(scope, year)
    [term | _] = Organization.list_terms(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    %{scope: scope, cg: cg, p1: p1, term: term}
  end

  defp paper_item(ctx),
    do:
      ctx.scope
      |> ReportCards.publish_checklist(ctx.cg, {:trimester, ctx.term})
      |> Enum.find(&(&1.key == :paper_roll_calls))

  test "a paper class with lessons not typed in gets a warning", ctx do
    # Mondays 8 and 15 September, before the clock's 13:00 on the 15th.
    assert %{ok?: false, data: %{count: 2}} = paper_item(ctx)
  end

  test "once the weeks are typed in, the item is fine", ctx do
    for monday <- [~D[2025-09-08], ~D[2025-09-15]] do
      {:ok, _} =
        Attendance.save_paper_week(ctx.scope, ctx.cg, monday, [
          %{date: monday, period_id: ctx.p1.id, mode: :taken, marks: %{}}
        ])
    end

    assert %{ok?: true, data: %{count: 0}} = paper_item(ctx)
  end

  test "a class off paper has no such item", ctx do
    {:ok, cg} = Enrollment.set_paper_roll_call(ctx.scope, ctx.cg, false)
    assert paper_item(%{ctx | cg: cg}) == nil
  end
end
