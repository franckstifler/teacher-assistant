defmodule TeacherAssistantWeb.TimetablePrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Print TT"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{conn: conn, school: school, cg: cg, period: period, head: head}
  end

  test "class timetable print shows the school, class label and a placed subject", %{
    conn: conn,
    cg: cg
  } do
    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    body = html_response(conn, 200)

    assert body =~ "Lycée Print TT"
    assert body =~ cg.label
    assert body =~ "Maths"
  end

  test "a non-admin non-form-master member is redirected from the class print", %{
    school: school,
    cg: cg,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(other)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    assert redirected_to(conn) == "/school"
  end

  test "the teacher's own timetable print shows their subject", %{conn: conn} do
    conn = get(conn, ~p"/school/timetable/me/print")
    body = html_response(conn, 200)

    assert body =~ "Maths"
  end

  test "the class print shows the room name", %{conn: conn, school: school, cg: cg, head: head} do
    scope = school_scope(head, school)
    {:ok, room} = Organization.create_room(scope, %{name: "Salle B12"})
    {:ok, _} = Enrollment.set_home_room(scope, cg, room.id)

    html = conn |> get(~p"/school/classes/#{cg.id}/timetable/print") |> html_response(200)
    assert html =~ "Salle B12"
  end

  describe "every teacher's timetable" do
    test "prints one sheet per teacher", %{conn: conn, school: school, cg: cg, head: head} do
      scope = school_scope(head, school)
      [_, p2 | _] = Attendance.list_periods(scope) |> Enum.filter(&(&1.kind == :lesson))
      zoe = TeacherAssistant.TeacherFixtures.user_fixture(%{name: "Zoé Ndzana"})

      %{teaching_context: tc} =
        TeacherAssistant.TeacherFixtures.school_teacher_fixture(scope, %{
          teacher: zoe,
          class_group: cg,
          subject: "SVT"
        })

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :tuesday,
          period_id: p2.id,
          teaching_context_id: tc.id
        })

      body = conn |> get(~p"/school/timetable/teachers/print") |> html_response(200)

      assert length(Regex.scan(~r/<section class="sheet"/, body)) == 2
      assert body =~ "Zoé Ndzana"
      assert body =~ "SVT"
      assert body =~ "Maths"
    end

    test "no timetable yet prints an empty page", %{
      conn: conn,
      school: school,
      cg: cg,
      head: head,
      period: period
    } do
      :ok = Timetabling.clear_slot(school_scope(head, school), cg, :monday, period.id)
      body = conn |> get(~p"/school/timetable/teachers/print") |> html_response(200)

      refute body =~ ~s(<section class="sheet")
      assert body =~ "Aucun cours placé"
    end

    test "a teacher is sent away", %{school: school, head: head} do
      teacher =
        TeacherAssistant.TeacherFixtures.member_scope_fixture(school_scope(head, school), %{
          roles: [:teacher]
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_user_in_session(teacher.current_user)
        |> Plug.Conn.put_session(:workspace_id, school.id)
        |> get(~p"/school/timetable/teachers/print")

      assert redirected_to(conn) == "/school"
    end

    test "belongs to the timetable module" do
      assert TeacherAssistant.Modules.module_for_controller(
               TeacherAssistantWeb.TimetablePrintController,
               :teachers
             ) == :emploi_du_temps
    end
  end

  describe "emploi du temps général" do
    test "one row per class in level order with code and teacher", %{
      conn: conn,
      school: school,
      cg: cg,
      head: head
    } do
      scope = school_scope(head, school)
      year = scope.current_academic_year
      {:ok, _} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})

      {:ok, _} =
        Attendance.update_school_days(scope, %{
          "lesson_days" => ~w(monday tuesday wednesday thursday friday),
          "default_lesson_minutes" => "55"
        })

      body = conn |> get(~p"/school/timetable/general/print") |> html_response(200)

      assert body =~ "EMPLOI DU TEMPS GÉNÉRAL"
      {six, _} = :binary.match(body, ">#{cg.label}<")
      {five, _} = :binary.match(body, ">5e A<")
      assert six < five
      assert body =~ "Maths"

      assert body =~
               TeacherAssistant.Accounts.User.short_name(
                 TeacherAssistant.Accounts.User.display_name(head)
               )

      refute body =~ "Samedi"
    end

    test "a school with classes but no lessons prints empty rows", %{
      conn: conn,
      school: school,
      cg: cg,
      head: head,
      period: period
    } do
      :ok = Timetabling.clear_slot(school_scope(head, school), cg, :monday, period.id)
      body = conn |> get(~p"/school/timetable/general/print") |> html_response(200)
      assert body =~ ">#{cg.label}<"
    end

    test "a teacher is sent away", %{school: school, head: head} do
      teacher =
        TeacherAssistant.TeacherFixtures.member_scope_fixture(school_scope(head, school), %{
          roles: [:teacher]
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_user_in_session(teacher.current_user)
        |> Plug.Conn.put_session(:workspace_id, school.id)
        |> get(~p"/school/timetable/general/print")

      assert redirected_to(conn) == "/school"
    end

    test "belongs to the timetable module" do
      assert TeacherAssistant.Modules.module_for_controller(
               TeacherAssistantWeb.TimetablePrintController,
               :general
             ) == :emploi_du_temps
    end
  end
end
