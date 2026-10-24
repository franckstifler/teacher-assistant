defmodule TeacherAssistantWeb.School.PastYearsTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Curriculum, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6ème A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user
    {:ok, _} = Curriculum.assign_teacher(scope, cg, teacher, %{subject: "Maths"})
    [seq | _] = Organization.list_sequences(scope, year)
    %{closed: closed} = TeacherFixtures.close_year!(scope, year)
    %{cg: cg, awa: awa, enrollment: e, teacher: teacher, seq: seq, closed: closed}
  end

  defp conn_for(user, school) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> put_user_in_session(user)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "settings opens a closed year, which lists its classes", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/year")

    assert has_element?(
             view,
             ~s|#year-row-#{ctx.closed.id}[href="/school/years/#{ctx.closed.id}"]|
           )

    {:ok, view, _} = live(conn, ~p"/school/years/#{ctx.closed.id}")
    assert has_element?(view, "#past-year", "Année de référence")

    assert has_element?(
             view,
             ~s|#past-class-#{ctx.cg.id} a[href="/school/classes/#{ctx.cg.id}/results"]|
           )
  end

  test "a past class's results use its own year and say it is closed", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{ctx.cg.id}/results")
    assert has_element?(view, "#year-closed", "Année de référence")
    # The period list is the closed year's, not the current one's.
    assert has_element?(view, ~s|option[value="seq:#{ctx.seq.id}"]|)

    {:ok, view, _} =
      live(conn, ~p"/school/classes/#{ctx.cg.id}/students/#{ctx.enrollment.id}/bulletin")

    assert has_element?(view, "#year-closed")
  end

  test "the printed bulletins of a past class name its year", %{conn: conn} = ctx do
    # The closed year's séquence only resolves against the class's own year.
    conn = get(conn, ~p"/school/classes/#{ctx.cg.id}/bulletin/print?period=seq:#{ctx.seq.id}")
    html = html_response(conn, 200)

    assert html =~ "Année de référence"
    # The current year is « Après Année de référence » — the bulletin must not name it.
    refute html =~ "Après Année de référence"
  end

  test "the student profile links to the past bulletin", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/students/#{ctx.awa.id}")

    assert has_element?(
             view,
             ~s|#student-history a[href="/school/classes/#{ctx.cg.id}/students/#{ctx.enrollment.id}/bulletin"]|
           )
  end

  test "the past class's teacher still opens its results; another teacher does not",
       %{scope: scope, workspace: school} = ctx do
    assert {:ok, _view, _} =
             live(conn_for(ctx.teacher, school), ~p"/school/classes/#{ctx.cg.id}/results")

    stranger = TeacherFixtures.member_scope_fixture(scope).current_user

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(stranger, school), ~p"/school/classes/#{ctx.cg.id}/results")
  end
end
