defmodule TeacherAssistantWeb.RollSheetPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Modules, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Feuille"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    for day <- [:monday, :tuesday] do
      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: day,
          period_id: p1.id,
          teaching_context_id: tc.id
        })
    end

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, scope: scope, year: year, cg: cg, school: school}
  end

  test "prints the class sheet for the week", %{conn: conn, cg: cg} do
    body =
      conn
      |> get(~p"/school/classes/#{cg.id}/roll-sheet/print?week=2025-09-17")
      |> html_response(200)

    assert body =~ "Feuille d&#39;appel"
    assert body =~ "6e A"
    assert body =~ "Semaine du lundi 15 au samedi 20 septembre 2025"
    assert body =~ "A = absent · R = retard"
    assert body =~ "Visa"
    assert body =~ "Awa"
    assert body =~ "MATH"
    assert body =~ "size: A4 landscape"
  end

  test "a holiday prints as a greyed band with its label", %{
    conn: conn,
    cg: cg,
    scope: scope,
    year: year
  } do
    {:ok, _} =
      Organization.create_holiday(scope, year, %{
        label: "Fête nationale",
        start_date: ~D[2025-09-16],
        end_date: ~D[2025-09-16]
      })

    body =
      conn
      |> get(~p"/school/classes/#{cg.id}/roll-sheet/print?week=2025-09-15")
      |> html_response(200)

    assert body =~ ~s(class="closed")
    assert body =~ "Fête nationale"
  end

  test "a class without students still prints its holiday band", %{
    conn: conn,
    scope: scope,
    year: year
  } do
    {:ok, empty} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, empty, scope.current_user, %{subject: "Maths"})
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    for day <- [:monday, :tuesday] do
      {:ok, _} =
        Timetabling.place_slot(scope, empty, %{
          day: day,
          period_id: p1.id,
          teaching_context_id: tc.id
        })
    end

    {:ok, _} =
      Organization.create_holiday(scope, year, %{
        label: "Fête nationale",
        start_date: ~D[2025-09-16],
        end_date: ~D[2025-09-16]
      })

    body =
      conn
      |> get(~p"/school/classes/#{empty.id}/roll-sheet/print?week=2025-09-15")
      |> html_response(200)

    assert body =~ ~s(class="closed")
    assert body =~ "Fête nationale"
  end

  test "all paper classes print, one page each", %{conn: conn, scope: scope, year: year} do
    {:ok, _} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    {:ok, off} = Enrollment.create_class_group(scope, year, %{label: "6e C", level: "6ème"})
    {:ok, _} = Enrollment.set_paper_roll_call(scope, off, false)

    body = conn |> get(~p"/school/roll-sheets/print?week=2025-09-15") |> html_response(200)

    assert length(String.split(body, ~s(class="sheet"))) - 1 == 2
    assert body =~ "6e B"
    refute body =~ "6e C"
  end

  test "a teacher is sent away", %{conn: conn, cg: cg, scope: scope, school: school} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      conn
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, school.id)
      |> get(~p"/school/classes/#{cg.id}/roll-sheet/print")

    assert redirected_to(conn) == ~p"/school"
  end

  test "the sheets belong to the roll-call module" do
    assert Modules.module_for_controller(TeacherAssistantWeb.RollSheetPrintController, :class) ==
             :appel

    assert Modules.module_for_controller(TeacherAssistantWeb.RollSheetPrintController, :all) ==
             :appel
  end
end
