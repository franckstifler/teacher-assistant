defmodule TeacherAssistantWeb.SpaceControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée S"})

    scope = school_scope(head, school)
    year = TeacherFixtures.complete_school_setup!(scope)
    %{school: school, scope: scope, year: year}
  end

  defp conn_for(school, user) do
    build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> put_user_in_session(user)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  defp censeur_who_teaches(%{school: school, scope: scope, year: year}) do
    member = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal, :teacher]})
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Curriculum.assign_teacher(scope, cg, member.current_user, %{subject: "Maths"})
    conn_for(school, member.current_user)
  end

  test "a member switches to one of their spaces and lands on its home", ctx do
    conn = censeur_who_teaches(ctx) |> post(~p"/school/space/enseignant")
    assert redirected_to(conn) == "/school/today"
    assert get_session(conn, :space) == "enseignant"
  end

  test "the member stays on their page when the new space's menu has it", ctx do
    member = censeur_who_teaches(ctx)
    conn = post(member, ~p"/school/space/enseignant?#{[return_to: "/school/courses"]}")
    assert redirected_to(conn) == "/school/courses"

    # the teacher's menu has no class list (they are not a form master): home
    conn = post(member, ~p"/school/space/enseignant?#{[return_to: "/school/classes/x"]}")

    assert redirected_to(conn) == "/school/today"
  end

  test "return_to never leaves the menu's pages", ctx do
    member = censeur_who_teaches(ctx)

    for target <- ["//evil.example/school/bulletins", "https://evil.example", "/admin", ""] do
      conn = post(member, ~p"/school/space/enseignant?#{[return_to: target]}")

      assert redirected_to(conn) == "/school/today"
    end
  end

  test "the space links carry the page the member is on", ctx do
    {:ok, view, _} = live(censeur_who_teaches(ctx), ~p"/school/bulletins")

    assert has_element?(
             view,
             ~s(#space-switch-enseignant[href="/school/space/enseignant?return_to=%2Fschool%2Fbulletins"])
           )
  end

  test "a space the member does not have is ignored", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    conn = conn_for(ctx.school, teacher.current_user) |> post(~p"/school/space/proviseur")
    assert redirected_to(conn) == "/school"
    assert get_session(conn, :space) == nil

    conn = conn_for(ctx.school, teacher.current_user) |> post(~p"/school/space/whatever")
    assert redirected_to(conn) == "/school"
  end

  test "a stored space whose role was removed falls back to the highest remaining one", ctx do
    member =
      TeacherFixtures.member_scope_fixture(ctx.scope, %{
        roles: [:vice_principal, :discipline_master]
      })

    conn = conn_for(ctx.school, member.current_user) |> Plug.Conn.put_session(:space, "censeur")

    {:ok, membership} = Accounts.fetch_school_membership(ctx.scope, member.current_user)
    {:ok, _} = Accounts.update_member_roles(ctx.scope, membership, [:discipline_master])

    {:ok, view, _} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-classes")
  end

  test "switching school forgets the chosen space", ctx do
    conn =
      censeur_who_teaches(ctx)
      |> Plug.Conn.put_session(:space, "enseignant")
      |> post(~p"/workspaces/select/#{ctx.school.id}")

    assert get_session(conn, :space) == nil
  end

  test "a controller page's menu follows the stored space", ctx do
    conn = censeur_who_teaches(ctx) |> post(~p"/school/space/enseignant")
    conn = conn |> recycle() |> post(~p"/school/space/whatever")
    assert conn.assigns.current_scope.capabilities.space.key == :enseignant
  end
end
