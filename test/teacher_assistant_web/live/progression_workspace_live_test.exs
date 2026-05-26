defmodule TeacherAssistantWeb.ProgressionWorkspaceLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest
  require Ash.Query

  setup %{conn: conn} do
    school = generate(school())
    admin = generate(admin_user(tenant: school))
    teacher = generate(user(tenant: school, role: :teacher))

    generate(user_school(tenant: school, user_id: admin.id, role: admin.role))
    generate(user_school(tenant: school, user_id: teacher.id, role: teacher.role))

    academic_year = generate(academic_year(tenant: school, actor: admin))
    level_option = generate(level_option(tenant: school, actor: admin))
    subject = generate(subject(tenant: school, actor: admin, name: "Mathematics"))

    level_option_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: subject.id, coefficient: 4},
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

    Ash.create!(
      TeacherAssistant.Academics.TeachingAssignment,
      %{
        classroom_id: classroom.id,
        level_option_subject_id: level_option_subject.id,
        teacher_id: teacher.id
      },
      tenant: school,
      actor: admin,
      authorize?: false
    )

    plan =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionPlan,
        %{
          academic_year_id: academic_year.id,
          classroom_id: classroom.id,
          level_option_subject_id: level_option_subject.id,
          teacher_id: teacher.id,
          weekly_hours: Decimal.new("4"),
          annual_hours: Decimal.new("96"),
          status: :active
        },
        tenant: school,
        actor: admin,
        authorize?: false
      )

    entry =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionEntry,
        %{
          progression_plan_id: plan.id,
          term_id: hd(academic_year.terms).id,
          week_number: 1,
          start_date: Date.utc_today(),
          end_date: Date.add(Date.utc_today(), 4),
          title: "Linear equations",
          planned_content: "Solving first-degree equations",
          planned_hours: Decimal.new("4"),
          entry_type: :lesson
        },
        tenant: school,
        actor: admin,
        authorize?: false
      )

    %{
      conn: log_in_user(conn, school, teacher),
      tenant: school,
      teacher: teacher,
      plan: plan,
      entry: entry
    }
  end

  test "teacher logs progression and creates an APC structure", %{
    conn: conn,
    tenant: tenant,
    teacher: teacher,
    plan: plan,
    entry: entry
  } do
    {:ok, view, _html} = live(conn, "/teacher/progression")

    assert has_element?(view, "#progression-plan-#{plan.id}")
    assert has_element?(view, "#progression-entry-#{entry.id}")
    assert has_element?(view, "#coverage-rate-#{plan.id}")

    assert view
           |> form("#teaching-log-form-#{entry.id}",
             teaching_log: %{
               taught_on: Date.to_iso8601(Date.utc_today()),
               taught_hours: "3",
               notes: "Exercises started"
             }
           )
           |> render_submit()

    log =
      TeacherAssistant.Academics.TeachingLog
      |> Ash.Query.filter(progression_entry_id == ^entry.id)
      |> Ash.read_one!(tenant: tenant, actor: teacher)

    assert Decimal.equal?(log.taught_hours, Decimal.new("3"))

    assert view
           |> form("#apc-lesson-form-#{entry.id}",
             apc_lesson_plan: %{
               competence: "Solve a real-life problem with first-degree equations",
               prerequisites: "Arithmetic operations",
               situation_problem: "Unknown unit price at the market",
               learning_activities: "Observe, model, solve, verify",
               resources: "Board, exercise sheet",
               evaluation: "Individual exercise",
               remediation: "Guided correction",
               duration_minutes: "55"
             }
           )
           |> render_submit()

    lesson =
      TeacherAssistant.Academics.ApcLessonPlan
      |> Ash.Query.filter(progression_entry_id == ^entry.id)
      |> Ash.read_one!(tenant: tenant, actor: teacher)

    assert lesson.competence =~ "real-life"
  end
end
