defmodule TeacherAssistantWeb.TypedAbsenceBulletinTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{
    Attendance,
    Enrollment,
    Organization,
    ReportCards,
    Scope,
    TeacherFixtures
  }

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, workspace: ws} do
    scope = %{scope | current_academic_year: year}
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    [%{enrollment: awa} | _] = Enrollment.list_roster(scope, cg)
    [t1 | _] = Organization.list_terms(scope, year)
    [s1 | _] = Enum.sort_by(t1.sequences, & &1.position_in_term)
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{scope: scope, cg: cg, awa: awa, t1: t1, s1: s1, op: op, ws: ws}
  end

  defp typed(ctx, source) do
    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, source)
    cg
  end

  defp print(conn, cg, period),
    do:
      html_response(get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=#{period}"), 200)

  test "typed class print shows only unjustified hours", %{conn: conn} = ctx do
    cg = typed(ctx, :typed_per_term)

    :ok =
      Attendance.save_typed_absences(ctx.scope, cg, {:trimester, ctx.t1}, %{ctx.awa.id => "7"})

    body = print(conn, cg, "trim:#{ctx.t1.id}")
    assert body =~ ~r/Absences non justifiées<\/td>\s*<td class="v">7/
    refute body =~ "Absences justifiées"
    refute body =~ "Retards"
  end

  test "a roll-call class keeps its three rows", %{conn: conn} = ctx do
    body = print(conn, ctx.cg, "trim:#{ctx.t1.id}")
    assert body =~ "Absences justifiées"
    assert body =~ "Retards"
  end

  test "no-appel school without typed figures has no absence row", %{conn: conn} = ctx do
    {:ok, _} = Organization.set_modules(ctx.op, ctx.ws, [:notes, :discipline])
    refute print(conn, ctx.cg, "trim:#{ctx.t1.id}") =~ "Absences non justifiées"
  end

  test "no-appel school with a typed figure shows it", %{conn: conn} = ctx do
    {:ok, ws} = Organization.set_modules(ctx.op, ctx.ws, [:notes, :discipline])
    scope = %{ctx.scope | current_workspace: ws}
    :ok = Attendance.save_typed_absences(scope, ctx.cg, {:sequence, ctx.s1}, %{ctx.awa.id => "2"})

    body = print(conn, ctx.cg, "trim:#{ctx.t1.id}")
    assert body =~ ~r/Absences non justifiées<\/td>\s*<td class="v">2/
    refute body =~ "Retards"
  end

  test "per_term séquence bulletin has no absence row", %{conn: conn} = ctx do
    cg = typed(ctx, :typed_per_term)
    refute print(conn, cg, "seq:#{ctx.s1.id}") =~ "Absences non justifiées"
  end

  defp item(ctx, cg, key),
    do:
      ctx.scope
      |> ReportCards.publish_checklist(cg, {:trimester, ctx.t1})
      |> Enum.find(&(&1.key == key))

  test "checklist warns for missing typed hours and skips paper_check", ctx do
    assert item(ctx, ctx.cg, :typed_absences) == nil

    cg = typed(ctx, :typed_per_term)
    missing = length(Enrollment.list_roster(ctx.scope, cg))
    assert %{ok?: false, data: %{missing: ^missing}} = item(ctx, cg, :typed_absences)
    assert item(ctx, cg, :paper_roll_calls) == nil

    rows = Map.new(Enrollment.list_roster(ctx.scope, cg), &{&1.enrollment.id, "0"})
    :ok = Attendance.save_typed_absences(ctx.scope, cg, {:trimester, ctx.t1}, rows)
    assert %{ok?: true, data: %{missing: 0}} = item(ctx, cg, :typed_absences)
  end

  test "no checklist item for a school with neither appel nor discipline", ctx do
    {:ok, ws} = Organization.set_modules(ctx.op, ctx.ws, [:notes])
    ctx = %{ctx | scope: %{ctx.scope | current_workspace: ws}}
    assert item(ctx, ctx.cg, :typed_absences) == nil
  end

  test "a published snapshot keeps its hours after a new save", ctx do
    cg = typed(ctx, :typed_per_term)
    period = {:trimester, ctx.t1}
    :ok = Attendance.save_typed_absences(ctx.scope, cg, period, %{ctx.awa.id => "3"})
    TeacherFixtures.publish_trimester(ctx.scope, cg, ctx.t1)
    :ok = Attendance.save_typed_absences(ctx.scope, cg, period, %{ctx.awa.id => "9"})

    assert {:published, _pub, snapshot} = ReportCards.class_view(ctx.scope, cg, period)
    assert Decimal.equal?(snapshot.conduct[ctx.awa.id].unjustified_hours, 3)
  end
end
