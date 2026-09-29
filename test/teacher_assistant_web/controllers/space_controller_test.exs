defmodule TeacherAssistantWeb.SpaceControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head} do
    {:ok, school} = Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée S"})
    scope = school_scope(head, school)
    year = TeacherFixtures.complete_school_setup!(scope)
    %{school: school, scope: scope, year: year}
  end

  defp conn_for(school, user) do
    build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  defp censeur_who_teaches(%{school: school, scope: scope, year: year}) do
    member = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal, :teacher]})
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Curriculum.assign_teacher(scope, cg, member.current_user, %{subject: "Maths"})
    conn_for(school, member.current_user)
  end

  test "a member switches to one of their spaces and lands on its home", ctx do
    conn = censeur_who_teaches(ctx) |> get(~p"/school/space/enseignant")
    assert redirected_to(conn) == "/school/courses"
    assert get_session(conn, :space) == "enseignant"
  end

  test "a space the member does not have is ignored", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    conn = conn_for(ctx.school, teacher.current_user) |> get(~p"/school/space/proviseur")
    assert redirected_to(conn) == "/school"
    assert get_session(conn, :space) == nil

    conn = conn_for(ctx.school, teacher.current_user) |> get(~p"/school/space/whatever")
    assert redirected_to(conn) == "/school"
  end

  test "a stored space whose role was removed falls back to the highest remaining one", ctx do
    member = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:vice_principal, :discipline_master]})
    conn = conn_for(ctx.school, member.current_user) |> Plug.Conn.put_session(:space, "censeur")

    {:ok, membership} = Accounts.fetch_school_membership(ctx.scope, member.current_user)
    {:ok, _} = Accounts.update_member_roles(ctx.scope, membership, [:discipline_master])

    {:ok, view, _} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-classes")
  end
end
