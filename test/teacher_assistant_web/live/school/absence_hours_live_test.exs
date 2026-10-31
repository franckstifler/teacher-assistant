defmodule TeacherAssistantWeb.School.AbsenceHoursLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Attendance, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year, workspace: ws} do
    scope = %{scope | current_academic_year: year}
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    [%{enrollment: awa}] = Enrollment.list_roster(scope, cg)
    [t1 | _] = Organization.list_terms(scope, year)
    [s1 | _] = Enum.sort_by(t1.sequences, & &1.position_in_term)
    %{scope: scope, ws: ws, year: year, cg: cg, awa: awa, t1: t1, s1: s1}
  end

  defp conn_for(ws, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> put_user_in_session(user)
    |> Plug.Conn.put_session(:workspace_id, ws.id)
  end

  defp form_master(ctx) do
    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)
    conn_for(ctx.ws, fm.current_user)
  end

  defp typed(ctx, source) do
    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, source)
    cg
  end

  defp page_path(ctx, period), do: ~p"/school/classes/#{ctx.cg.id}/absence-hours?period=#{period}"

  test "form master types and saves hours", ctx do
    cg = typed(ctx, :typed_per_sequence)
    {:ok, view, _} = live(form_master(ctx), page_path(ctx, "seq:#{ctx.s1.id}"))

    view
    |> form("#typed-absences-form", %{"hours" => %{ctx.awa.id => "4,5"}})
    |> render_submit()

    assert has_element?(view, ~s|input[name="hours[#{ctx.awa.id}]"][value="4,5"]|)
    refute has_element?(view, "#prefilled-#{ctx.awa.id}")

    assert Decimal.equal?(
             Attendance.bulletin_conduct(ctx.scope, cg, {:sequence, ctx.s1})[ctx.awa.id].unjustified_hours,
             Decimal.new("4.5")
           )
  end

  test "form master cannot change the source", ctx do
    typed(ctx, :typed_per_sequence)
    {:ok, view, _} = live(form_master(ctx), page_path(ctx, "seq:#{ctx.s1.id}"))
    assert has_element?(view, "#absence-source")
    refute has_element?(view, "#absence-source select")
  end

  test "conduct manager switches the class to typed per term", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/absence-hours")

    view
    |> form("#absence-source-form", %{"source" => "typed_per_term"})
    |> render_change()

    {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, ctx.cg.id)
    assert cg.absence_hours_source == :typed_per_term
    assert has_element?(view, "#typed-absences-form")
  end

  test "roll-call class shows the note and no form", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/absence-hours")
    assert has_element?(view, "#roll-call-note")
    refute has_element?(view, "#typed-absences-form")
  end

  test "pre-filled rows are marked", %{conn: conn} = ctx do
    typed(ctx, :typed_per_sequence)
    {:ok, view, _} = live(conn, page_path(ctx, "seq:#{ctx.s1.id}"))
    # No roll call taken: the app's hours are 0, offered as a suggestion.
    assert has_element?(view, "#prefilled-#{ctx.awa.id}")
    assert has_element?(view, "#app-hours-#{ctx.awa.id}")
  end

  test "invalid row shows the error and saves nothing", %{conn: conn} = ctx do
    cg = typed(ctx, :typed_per_sequence)
    {:ok, view, _} = live(conn, page_path(ctx, "seq:#{ctx.s1.id}"))

    view
    |> form("#typed-absences-form", %{"hours" => %{ctx.awa.id => "-2"}})
    |> render_submit()

    assert has_element?(view, "#hours-error-#{ctx.awa.id}")

    refute Attendance.bulletin_conduct(ctx.scope, cg, {:sequence, ctx.s1})[ctx.awa.id].recorded?
  end

  test "published trimester shows the warning", %{conn: conn} = ctx do
    cg = typed(ctx, :typed_per_term)
    TeacherFixtures.publish_trimester(ctx.scope, cg, ctx.t1)
    {:ok, view, _} = live(conn, page_path(ctx, "trim:#{ctx.t1.id}"))
    assert has_element?(view, "#published-warning")
  end

  test "a teacher who is not form master is redirected", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    assert {:error, {_kind, _}} =
             live(
               conn_for(ctx.ws, teacher.current_user),
               ~p"/school/classes/#{ctx.cg.id}/absence-hours"
             )
  end

  test "the discipline tab links to the screen", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/discipline")
    assert has_element?(view, ~s|a[href="/school/classes/#{ctx.cg.id}/absence-hours"]|)
  end

  test "settings set every class at once", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/school-life")
    view |> element("#absence-source-all-typed_per_term") |> render_click()

    assert ctx.scope
           |> Enrollment.list_class_groups(ctx.year)
           |> Enum.all?(&(&1.absence_hours_source == :typed_per_term))
  end
end
