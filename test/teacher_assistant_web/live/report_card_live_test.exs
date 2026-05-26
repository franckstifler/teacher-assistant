defmodule TeacherAssistantWeb.ReportCardLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    school = generate(school())
    admin = generate(admin_user(tenant: school))
    generate(user_school(tenant: school, user_id: admin.id, role: admin.role))

    academic_year = generate(academic_year(tenant: school, actor: admin))
    [term] = academic_year.terms

    sequence =
      Ash.create!(
        TeacherAssistant.Academics.Sequence,
        %{
          term_id: term.id,
          name: "Sequence 1",
          start_date: term.start_date,
          end_date: term.end_date
        },
        tenant: school,
        actor: admin,
        authorize?: false
      )

    level_option = generate(level_option(tenant: school, actor: admin))
    mathematics = generate(subject(tenant: school, actor: admin, name: "Mathematics"))
    english = generate(subject(tenant: school, actor: admin, name: "English"))

    math_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: mathematics.id, coefficient: 5},
        authorize?: false
      )

    english_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: english.id, coefficient: 3},
        authorize?: false
      )

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: school,
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms

    student =
      generate(student(tenant: school, actor: admin, first_name: "Alice", last_name: "Mvondo"))

    Ash.create!(
      TeacherAssistant.Academics.ClassroomStudent,
      %{classroom_id: classroom.id, student_id: student.id},
      tenant: school,
      actor: admin,
      authorize?: false
    )

    Ash.create!(
      TeacherAssistant.Academics.Mark,
      %{
        student_id: student.id,
        classroom_id: classroom.id,
        sequence_id: sequence.id,
        level_option_subject_id: math_subject.id,
        score: Decimal.new("16")
      },
      tenant: school,
      actor: admin,
      authorize?: false
    )

    Ash.create!(
      TeacherAssistant.Academics.Mark,
      %{
        student_id: student.id,
        classroom_id: classroom.id,
        sequence_id: sequence.id,
        level_option_subject_id: english_subject.id,
        score: Decimal.new("12")
      },
      tenant: school,
      actor: admin,
      authorize?: false
    )

    Ash.create!(
      TeacherAssistant.Academics.Attendance,
      %{
        student_id: student.id,
        classroom_id: classroom.id,
        date: term.start_date,
        status: :absent,
        comment: "Absent"
      },
      tenant: school,
      actor: admin,
      authorize?: false
    )

    %{
      conn: log_in_user(conn, school, admin),
      academic_year: academic_year,
      term: term,
      classroom: classroom,
      student: student
    }
  end

  test "admin previews deterministic report cards", %{
    conn: conn,
    academic_year: academic_year,
    term: term,
    classroom: classroom,
    student: student
  } do
    {:ok, view, _html} = live(conn, "/reports/report_cards")

    assert has_element?(view, "#report-card-filter")

    assert view
           |> form("#report-card-filter",
             filters: %{academic_year_id: academic_year.id, term_id: "", classroom_id: ""}
           )
           |> render_change()

    assert view
           |> form("#report-card-filter",
             filters: %{
               academic_year_id: academic_year.id,
               term_id: term.id,
               classroom_id: classroom.id
             }
           )
           |> render_change()

    assert has_element?(view, "#report-cards-table")
    assert has_element?(view, "#report-card-row-#{student.id}")
    assert has_element?(view, "#report-average-#{student.id}", "14.50")
    assert has_element?(view, "#report-rank-#{student.id}", "1")
    assert has_element?(view, "#report-absences-#{student.id}", "1")
  end
end
