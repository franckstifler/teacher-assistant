defmodule TeacherAssistantWeb.StudentAccessLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    school = generate(school())
    admin = generate(admin_user(tenant: school))
    generate(user_school(tenant: school, user_id: admin.id, role: admin.role))

    academic_year = generate(academic_year(tenant: school, actor: admin))
    level_option = generate(level_option(tenant: school, actor: admin))

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: school,
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms
    student = generate(student(tenant: school, actor: admin))

    enrollment =
      Ash.create!(
        TeacherAssistant.Academics.ClassroomStudent,
        %{classroom_id: classroom.id, student_id: student.id},
        tenant: school,
        actor: admin,
        authorize?: false
      )

    accountant = generate(user(tenant: school, role: :accountant))
    generate(user_school(tenant: school, user_id: accountant.id, role: accountant.role))

    %{
      conn: log_in_user(conn, school, accountant),
      tenant: school,
      accountant: accountant,
      classroom: classroom,
      enrollment: enrollment
    }
  end

  test "accountant suspends a classroom enrollment", %{
    conn: conn,
    tenant: tenant,
    accountant: accountant,
    classroom: classroom,
    enrollment: enrollment
  } do
    {:ok, view, _html} = live(conn, "/configurations/student_access")

    assert has_element?(view, "#student-access-filter")

    assert view
           |> form("#student-access-filter", filters: %{classroom_id: classroom.id})
           |> render_change()

    assert has_element?(view, "#student-access-table")
    assert has_element?(view, "#student-access-row-#{enrollment.id}")

    assert view
           |> form("#student-access-form-#{enrollment.id}",
             access: %{access_status: "suspended", access_note: "Fees pending"}
           )
           |> render_submit()

    updated =
      Ash.get!(
        TeacherAssistant.Academics.ClassroomStudent,
        enrollment.id,
        tenant: tenant,
        actor: accountant
      )

    assert updated.access_status == :suspended
    assert updated.access_note == "Fees pending"
    assert updated.access_set_by_id == accountant.id
    assert has_element?(view, "#access-status-#{enrollment.id}")
  end
end
