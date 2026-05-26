defmodule TeacherAssistantWeb.ProgrammeCoverageLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    school = generate(school())
    admin = generate(admin_user(tenant: school))
    vice_principal = generate(user(tenant: school, role: :vice_principal))
    teacher = generate(user(tenant: school, role: :teacher))

    generate(user_school(tenant: school, user_id: admin.id, role: admin.role))
    generate(user_school(tenant: school, user_id: vice_principal.id, role: vice_principal.role))
    generate(user_school(tenant: school, user_id: teacher.id, role: teacher.role))

    academic_year = generate(academic_year(tenant: school, actor: admin))
    level_option = generate(level_option(tenant: school, actor: admin))
    subject = generate(subject(tenant: school, actor: admin, name: "Physics"))

    level_option_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: subject.id, coefficient: 3},
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

    plan =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionPlan,
        %{
          academic_year_id: academic_year.id,
          classroom_id: classroom.id,
          level_option_subject_id: level_option_subject.id,
          teacher_id: teacher.id,
          weekly_hours: Decimal.new("3"),
          annual_hours: Decimal.new("72"),
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
          week_number: 1,
          title: "Forces",
          planned_hours: Decimal.new("4")
        },
        tenant: school,
        actor: admin,
        authorize?: false
      )

    Ash.create!(
      TeacherAssistant.Academics.TeachingLog,
      %{
        progression_entry_id: entry.id,
        taught_on: Date.utc_today(),
        taught_hours: Decimal.new("3"),
        notes: "Covered examples"
      },
      tenant: school,
      actor: teacher,
      authorize?: false
    )

    %{conn: log_in_user(conn, school, vice_principal), plan: plan}
  end

  test "vice principal sees programme coverage rates", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, "/reports/programme_coverage")

    assert has_element?(view, "#programme-coverage-table")
    assert has_element?(view, "#coverage-row-#{plan.id}")
    assert has_element?(view, "#coverage-rate-#{plan.id}", "75.00%")
  end
end
