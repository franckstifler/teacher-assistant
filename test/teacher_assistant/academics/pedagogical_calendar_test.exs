defmodule TeacherAssistant.Academics.PedagogicalCalendarTest do
  use TeacherAssistant.DataCase

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.PedagogicalCalendar
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.TeachingLog

  setup %{tenant: tenant, user: admin} do
    teacher = generate(user(tenant: tenant, role: :teacher))
    other_teacher = generate(user(tenant: tenant, role: :teacher))
    generate(user_school(tenant: tenant, user_id: teacher.id, role: teacher.role))
    generate(user_school(tenant: tenant, user_id: other_teacher.id, role: other_teacher.role))

    plan = create_plan!(tenant, admin, teacher, "Mathematics")
    other_plan = create_plan!(tenant, admin, other_teacher, "Physics")
    scope = Workspaces.scope_for!(teacher, tenant.id)

    %{
      tenant: tenant,
      admin: admin,
      teacher: teacher,
      scope: scope,
      plan: plan,
      other_plan: other_plan
    }
  end

  test "lists only current teacher activities in the current tenant", %{
    tenant: tenant,
    admin: admin,
    scope: scope,
    plan: plan,
    other_plan: other_plan
  } do
    entry = create_entry!(tenant, admin, plan, week_number: 1, title: "Visible lesson")
    create_entry!(tenant, admin, other_plan, week_number: 1, title: "Other teacher lesson")

    assert {:ok, activities} = PedagogicalCalendar.list_activities(scope, %{date: ~D[2026-09-02]})
    assert Enum.map(activities, & &1.entry_id) == [entry.id]
  end

  test "derives planned, due, late, partially taught, and completed statuses", %{
    tenant: tenant,
    admin: admin,
    scope: scope,
    plan: plan
  } do
    create_entry!(tenant, admin, plan,
      week_number: 1,
      title: "Future",
      start_date: ~D[2026-09-21],
      end_date: ~D[2026-09-25],
      planned_hours: Decimal.new("4")
    )

    create_entry!(tenant, admin, plan,
      week_number: 2,
      title: "Due",
      start_date: ~D[2026-09-14],
      end_date: ~D[2026-09-18],
      planned_hours: Decimal.new("4")
    )

    create_entry!(tenant, admin, plan,
      week_number: 3,
      title: "Late",
      start_date: ~D[2026-09-01],
      end_date: ~D[2026-09-04],
      planned_hours: Decimal.new("4")
    )

    partial =
      create_entry!(tenant, admin, plan,
        week_number: 4,
        title: "Partial",
        start_date: ~D[2026-09-08],
        end_date: ~D[2026-09-12],
        planned_hours: Decimal.new("4")
      )

    complete =
      create_entry!(tenant, admin, plan,
        week_number: 5,
        title: "Complete",
        start_date: ~D[2026-09-08],
        end_date: ~D[2026-09-12],
        planned_hours: Decimal.new("4")
      )

    create_log!(tenant, admin, partial, taught_hours: Decimal.new("2"))
    create_log!(tenant, admin, complete, taught_hours: Decimal.new("4"))

    assert {:ok, activities} = PedagogicalCalendar.list_activities(scope, %{date: ~D[2026-09-16]})
    statuses = Map.new(activities, &{&1.title, &1.status})

    assert statuses["Future"] == :planned
    assert statuses["Due"] == :due_today
    assert statuses["Late"] == :late
    assert statuses["Partial"] == :partially_taught
    assert statuses["Complete"] == :completed
  end

  test "filters today, week, and month ranges", %{
    tenant: tenant,
    admin: admin,
    scope: scope,
    plan: plan
  } do
    today =
      create_entry!(tenant, admin, plan,
        week_number: 1,
        title: "Today",
        start_date: ~D[2026-09-16],
        end_date: ~D[2026-09-16]
      )

    week =
      create_entry!(tenant, admin, plan,
        week_number: 2,
        title: "This week",
        start_date: ~D[2026-09-18],
        end_date: ~D[2026-09-20]
      )

    month =
      create_entry!(tenant, admin, plan,
        week_number: 3,
        title: "This month",
        start_date: ~D[2026-09-28],
        end_date: ~D[2026-09-30]
      )

    create_entry!(tenant, admin, plan,
      week_number: 4,
      title: "Outside",
      start_date: ~D[2026-10-02],
      end_date: ~D[2026-10-03]
    )

    create_entry!(tenant, admin, plan,
      week_number: 5,
      title: "Unscheduled",
      start_date: nil,
      end_date: nil
    )

    assert {:ok, today_activities} =
             PedagogicalCalendar.list_activities(scope, %{mode: :today, date: ~D[2026-09-16]})

    assert Enum.map(today_activities, & &1.entry_id) == [today.id]

    assert {:ok, week_activities} =
             PedagogicalCalendar.list_activities(scope, %{mode: :week, date: ~D[2026-09-16]})

    assert Enum.map(week_activities, & &1.entry_id) == [today.id, week.id]

    assert {:ok, month_activities} =
             PedagogicalCalendar.list_activities(scope, %{mode: :month, date: ~D[2026-09-16]})

    assert Enum.map(month_activities, & &1.entry_id) == [today.id, week.id, month.id]
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

  defp create_entry!(tenant, admin, plan, attrs) do
    Ash.create!(
      ProgressionEntry,
      Keyword.merge(
        [
          progression_plan_id: plan.id,
          week_number: 1,
          start_date: ~D[2026-09-01],
          end_date: ~D[2026-09-05],
          title: "Lesson",
          planned_content: "Content",
          planned_hours: Decimal.new("4"),
          entry_type: :lesson
        ],
        attrs
      )
      |> Map.new(),
      tenant: tenant,
      actor: admin,
      authorize?: false
    )
  end

  defp create_log!(tenant, admin, entry, attrs) do
    Ash.create!(
      TeachingLog,
      Keyword.merge(
        [
          progression_entry_id: entry.id,
          taught_on: entry.start_date || ~D[2026-09-01],
          taught_hours: Decimal.new("1"),
          notes: "Done"
        ],
        attrs
      )
      |> Map.new(),
      tenant: tenant,
      actor: admin,
      authorize?: false
    )
  end
end
