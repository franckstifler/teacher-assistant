defmodule TeacherAssistantWeb.TeacherCalendarLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  require Ash.Query

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.TeachingLog

  setup %{conn: conn} do
    school = generate(school())
    admin = generate(admin_user(tenant: school))
    teacher = generate(user(tenant: school, role: :teacher))
    other_teacher = generate(user(tenant: school, role: :teacher))

    generate(user_school(tenant: school, user_id: admin.id, role: admin.role))
    generate(user_school(tenant: school, user_id: teacher.id, role: teacher.role))
    generate(user_school(tenant: school, user_id: other_teacher.id, role: other_teacher.role))

    plan = create_plan!(school, admin, teacher, "Mathematics")

    other_plan =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionPlan,
        %{
          academic_year_id: plan.academic_year_id,
          classroom_id: plan.classroom_id,
          level_option_subject_id: plan.level_option_subject_id,
          teacher_id: other_teacher.id,
          weekly_hours: Decimal.new("4"),
          annual_hours: Decimal.new("96"),
          status: :active
        },
        tenant: school,
        actor: admin,
        authorize?: false
      )

    %{
      conn: log_in_user(conn, school, teacher),
      tenant: school,
      admin: admin,
      teacher: teacher,
      plan: plan,
      other_plan: other_plan
    }
  end

  test "teacher sees calendar navigation", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/teacher/calendar")

    assert html =~ "teacher-calendar"
    assert html =~ ~s(id="nav-teacher-calendar")
  end

  test "today view shows due and late activities for the current teacher", %{
    conn: conn,
    tenant: tenant,
    admin: admin,
    plan: plan,
    other_plan: other_plan
  } do
    today = Date.utc_today()

    due =
      create_entry!(tenant, admin, plan,
        week_number: 1,
        title: "Due lesson",
        start_date: today,
        end_date: today
      )

    late =
      create_entry!(tenant, admin, plan,
        week_number: 2,
        title: "Late lesson",
        start_date: Date.add(today, -7),
        end_date: Date.add(today, -5)
      )

    create_entry!(tenant, admin, other_plan,
      week_number: 3,
      title: "Other teacher lesson",
      start_date: today,
      end_date: today
    )

    {:ok, view, _html} = live(conn, ~p"/teacher/calendar")

    assert has_element?(view, "#calendar-activity-#{due.id}")
    assert has_element?(view, "#calendar-activity-#{late.id}")
    assert has_element?(view, "#calendar-status-#{due.id}", "Due today")
    assert has_element?(view, "#calendar-status-#{late.id}", "Late")
    refute render(view) =~ "Other teacher lesson"
  end

  test "week and month calendar modes show matching activities", %{
    conn: conn,
    tenant: tenant,
    admin: admin,
    plan: plan
  } do
    today = Date.utc_today()
    monday = Date.add(today, -(Date.day_of_week(today) - 1))

    week_entry =
      create_entry!(tenant, admin, plan,
        week_number: 1,
        title: "Week lesson",
        start_date: Date.add(monday, 2),
        end_date: Date.add(monday, 4)
      )

    month_entry =
      create_entry!(tenant, admin, plan,
        week_number: 2,
        title: "Month lesson",
        start_date: Date.end_of_month(today),
        end_date: Date.end_of_month(today)
      )

    {:ok, view, _html} = live(conn, ~p"/teacher/calendar")

    view |> element("#calendar-mode-week") |> render_click()
    assert has_element?(view, "#calendar-activity-#{week_entry.id}")

    view |> element("#calendar-mode-month") |> render_click()
    assert has_element?(view, "#calendar-day-#{Date.to_iso8601(month_entry.start_date)}")
    assert has_element?(view, "#calendar-activity-#{month_entry.id}")
  end

  test "logging an activity updates its derived status", %{
    conn: conn,
    tenant: tenant,
    admin: admin,
    teacher: teacher,
    plan: plan
  } do
    today = Date.utc_today()

    entry =
      create_entry!(tenant, admin, plan,
        week_number: 1,
        title: "Loggable lesson",
        start_date: today,
        end_date: today,
        planned_hours: Decimal.new("4")
      )

    {:ok, view, _html} = live(conn, ~p"/teacher/calendar")

    assert has_element?(view, "#calendar-status-#{entry.id}", "Due today")

    assert view
           |> form("#calendar-log-form-#{entry.id}",
             teaching_log: %{
               taught_on: Date.to_iso8601(today),
               taught_hours: "4",
               notes: "Completed from calendar"
             }
           )
           |> render_submit()

    assert has_element?(view, "#calendar-status-#{entry.id}", "Completed")

    log =
      TeachingLog
      |> Ash.Query.filter(progression_entry_id == ^entry.id)
      |> Ash.read_one!(tenant: tenant, actor: teacher)

    assert log.notes == "Completed from calendar"
  end

  test "personal teacher sees personal calendar activities", %{conn: conn} do
    teacher = generate(user_without_school(role: :teacher))
    workspace = Workspaces.ensure_personal_workspace!(teacher)
    scope = Workspaces.scope_for!(teacher, workspace.id)

    {:ok, setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2026-2027",
        "start_date" => "2026-09-01",
        "end_date" => "2027-06-30",
        "class_name" => "Form 5",
        "option_name" => "Science",
        "subject_name" => "Mathematics"
      })

    {:ok, plan} =
      PersonalWorkspace.create_progression_plan(scope, %{
        "academic_year_id" => setup.academic_year.id,
        "classroom_id" => setup.classroom.id,
        "level_option_subject_id" => setup.level_option_subject.id,
        "weekly_hours" => "4",
        "annual_hours" => "96"
      })

    entry =
      create_entry!(workspace, teacher, plan,
        week_number: 1,
        title: "Personal lesson",
        start_date: Date.utc_today(),
        end_date: Date.utc_today()
      )

    {:ok, view, _html} =
      conn
      |> log_in_user(workspace, teacher)
      |> live(~p"/teacher/calendar")

    assert has_element?(view, "#calendar-activity-#{entry.id}")
  end

  defp create_plan!(tenant, admin, teacher, subject_name) do
    academic_year = generate(academic_year(tenant: tenant, actor: admin))
    level_option = generate(level_option(tenant: tenant, actor: admin))
    subject = generate(subject(tenant: tenant, actor: admin, name: subject_name))

    level_option_subject =
      Ash.create!(
        TeacherAssistant.Academics.LevelOptionSubject,
        %{level_option_id: level_option.id, subject_id: subject.id, coefficient: 4},
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: tenant,
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms

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
      tenant: tenant,
      actor: admin,
      authorize?: false
    )
  end

  defp create_entry!(tenant, actor, plan, attrs) do
    Ash.create!(
      ProgressionEntry,
      Keyword.merge(
        [
          progression_plan_id: plan.id,
          week_number: 1,
          start_date: Date.utc_today(),
          end_date: Date.utc_today(),
          title: "Lesson",
          planned_content: "Content",
          planned_hours: Decimal.new("4"),
          entry_type: :lesson
        ],
        attrs
      )
      |> Map.new(),
      tenant: tenant,
      actor: actor,
      authorize?: false
    )
  end
end
