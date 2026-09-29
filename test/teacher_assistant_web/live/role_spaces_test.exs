defmodule TeacherAssistantWeb.RoleSpacesTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head} do
    {:ok, school} = Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée R"})
    scope = school_scope(head, school)
    year = TeacherFixtures.complete_school_setup!(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    %{school: school, scope: scope, cg: cg}
  end

  defp member_conn(ctx, roles, opts) do
    member = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: roles})

    tc =
      if opts[:teaches?],
        do: elem(Curriculum.assign_teacher(ctx.scope, ctx.cg, member.current_user, %{subject: "Maths"}), 1)

    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, member.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ctx.school.id)

    {conn, tc}
  end

  test "a teacher sees only their teaching menu, without a switcher", ctx do
    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#nav-school-courses")
    assert has_element?(view, "#nav-school-timetable-me")
    refute has_element?(view, "#nav-school-dashboard")
    refute has_element?(view, "#nav-school-settings")
    refute has_element?(view, "#space-switcher")
  end

  test "a censeur who teaches switches between Censeur and Enseignant", ctx do
    {conn, _} = member_conn(ctx, [:vice_principal, :teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#space-switch-censeur[aria-current]")
    assert has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-coefficients")

    conn = get(conn, ~p"/school/space/enseignant")
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#space-switch-enseignant[aria-current]")
    refute has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-courses")
  end

  test "a hidden screen stays read-only when typed directly", ctx do
    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/settings")
    refute has_element?(view, "#year-form")
    refute has_element?(view, "#subject-form")
  end

  test "inside a course the per-course menu still shows", ctx do
    {conn, tc} = member_conn(ctx, [:teacher], teaches?: true)
    conn = get(conn, ~p"/teacher/select-context/#{tc.id}")
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/marks")
    assert has_element?(view, "#per-class-nav")
    assert has_element?(view, "#nav-school-courses")
  end
end
