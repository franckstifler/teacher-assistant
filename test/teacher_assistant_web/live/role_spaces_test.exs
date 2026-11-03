defmodule TeacherAssistantWeb.RoleSpacesTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée R"})

    scope = school_scope(head, school)
    year = TeacherFixtures.complete_school_setup!(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    %{school: school, scope: scope, cg: cg}
  end

  defp member_conn(ctx, roles, opts) do
    member = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: roles})

    tc =
      if opts[:teaches?],
        do:
          elem(
            Curriculum.assign_teacher(ctx.scope, ctx.cg, member.current_user, %{subject: "Maths"}),
            1
          )

    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(member.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.school.id)

    {conn, tc}
  end

  test "a teacher sees only their teaching menu, without a switcher", ctx do
    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#nav-school-courses")
    assert has_element?(view, "#nav-school-timetable-me")
    refute has_element?(view, "#nav-school-dashboard")
    refute has_element?(view, "#nav-school-sequences")
    refute has_element?(view, "#nav-school-settings")
    refute has_element?(view, "#space-switcher")
  end

  test "a censeur who teaches switches between Censeur and Enseignant", ctx do
    {conn, _} = member_conn(ctx, [:vice_principal, :teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#space-switch-censeur[aria-current]")
    assert has_element?(view, "#nav-school-sequences")
    assert has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-settings")
    refute has_element?(view, "#nav-school-coefficients")

    conn = post(conn, ~p"/school/space/enseignant")
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#space-switch-enseignant[aria-current]")
    refute has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-courses")
  end

  test "on phones the space's tab bar leads, the rest sits in the « Plus » sheet", ctx do
    {conn, tc} = member_conn(ctx, [:vice_principal, :teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/sequences")
    assert has_element?(view, "#tab-nav-school-sequences[aria-current=page]")
    assert has_element?(view, "#tab-nav-school-timetable-editor")
    assert has_element?(view, "#tab-more[popovertarget=more-sheet]")
    assert has_element?(view, "#more-sheet #more-nav-school-members")
    refute has_element?(view, "#more-sheet #more-nav-school-sequences")
    assert has_element?(view, "#more-sheet #sheet-space-enseignant")

    conn = post(conn, ~p"/school/space/enseignant")
    conn = post(conn, ~p"/teacher/select-context/#{tc.id}")
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/marks/summary")
    # a course's pages belong to « Mes cours », on the phone and on the rail
    assert has_element?(view, "#tab-nav-school-courses[aria-current=page]")
    assert has_element?(view, "#nav-school-courses[aria-current=page]")
    assert has_element?(view, "#tab-nav-school-bulletins")

    # entering marks is a full-screen task on phones: no tab bar, the rail stays
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/marks")
    refute has_element?(view, "#tab-nav-school-courses")
    assert has_element?(view, "#nav-school-courses[aria-current=page]")
  end

  test "a hidden screen stays read-only when typed directly", ctx do
    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/settings")
    refute has_element?(view, "#year-form")
    refute has_element?(view, "#subject-form")
  end

  test "inside a course its tabs show, with the space menu", ctx do
    {conn, tc} = member_conn(ctx, [:teacher], teaches?: true)
    conn = post(conn, ~p"/teacher/select-context/#{tc.id}")
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/marks")
    assert has_element?(view, "#teaching-nav")
    assert has_element?(view, "#nav-school-courses")
  end

  test "the rail shows correction counts", ctx do
    {conn, _} = member_conn(ctx, [:vice_principal], [])
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#nav-school-correction-review")
    refute has_element?(view, "#nav-school-correction-review .badge")

    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#nav-school-corrections")
  end

  test "the rail names the space, the « Plus » sheet keeps the rail's sections", ctx do
    {conn, _} = member_conn(ctx, [:vice_principal, :teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/sequences")

    assert has_element?(view, "#workspace-switcher", "Espace censeur")
    assert has_element?(view, "#workspace-switcher-item-#{ctx.school.id} a[aria-current]")
    assert has_element?(view, "#nav-school-correction-review", "Validation des corrections")
    assert has_element?(view, "#more-nav section", "Suivi pédagogique")
    assert has_element?(view, "#more-nav section", "Scolarité")
    assert has_element?(view, "#more-nav section", "Organisation")

    conn = post(conn, ~p"/school/space/enseignant")
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#workspace-switcher", "Espace enseignant")
    assert has_element?(view, "#nav-school-corrections", "Corrections de notes")
  end

  test "« Photos examen » opens from Élèves, which stays lit", ctx do
    {conn, _} = member_conn(ctx, [:head], [])
    {:ok, view, _} = live(conn, ~p"/school/students")
    refute has_element?(view, "#nav-school-exam-photos")
    assert has_element?(view, ~s(#go-to-exam-photos[href="/school/exam-photos"]))

    {:ok, view, _} = live(conn, ~p"/school/exam-photos")
    assert has_element?(view, "#nav-school-students[aria-current=page]")
    assert has_element?(view, ~s(#exam-photos-back[href="/school/students"]))
  end

  test "only a head is offered to create a school in the switcher", ctx do
    {conn, _} = member_conn(ctx, [:head], [])
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#workspace-switcher-new")

    for roles <- [[:vice_principal], [:discipline_master], [:bursar]] do
      {conn, _} = member_conn(ctx, roles, [])
      {:ok, view, _} = live(conn, ~p"/school/classes")
      refute has_element?(view, "#workspace-switcher-new")
    end
  end

  test "a class's fees belong to Frais, not to Classes", ctx do
    {conn, _} = member_conn(ctx, [:head], [])
    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/fees")
    assert has_element?(view, "#nav-school-fees[aria-current=page]")
    refute has_element?(view, "#nav-school-classes[aria-current=page]")
    assert has_element?(view, "#class-tab-fees[aria-current=page]")
  end

  test "« Disponibilités » is a page of the timetable editor's entry", ctx do
    {conn, _} = member_conn(ctx, [:vice_principal], [])
    {:ok, view, _} = live(conn, ~p"/school/timetable/availability")
    refute has_element?(view, "#nav-school-availability")
    assert has_element?(view, "#nav-school-timetable-editor[aria-current=page]")
    assert has_element?(view, "#tab-nav-school-timetable-editor[aria-current=page]")

    {:ok, view, _} = live(conn, ~p"/school/timetable")
    assert has_element?(view, "#nav-school-timetable-editor[aria-current=page]")
  end
end
