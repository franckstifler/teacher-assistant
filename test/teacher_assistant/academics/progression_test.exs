defmodule TeacherAssistant.Academics.ProgressionTest do
  use TeacherAssistant.DataCase, async: true

  test "creates a progression plan with entries and a teaching log", %{tenant: tenant, user: user} do
    academic_year = Ash.Generator.generate(academic_year(tenant: tenant, actor: user))
    level_option = Ash.Generator.generate(level_option(tenant: tenant, actor: user))
    subject = Ash.Generator.generate(subject(tenant: tenant, actor: user))

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
        tenant: tenant,
        actor: user,
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
          teacher_id: user.id,
          weekly_hours: Decimal.new("4"),
          annual_hours: Decimal.new("96"),
          status: :draft
        },
        tenant: tenant,
        actor: user,
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
        tenant: tenant,
        actor: user,
        authorize?: false
      )

    log =
      Ash.create!(
        TeacherAssistant.Academics.TeachingLog,
        %{
          progression_entry_id: entry.id,
          taught_on: Date.utc_today(),
          taught_hours: Decimal.new("3"),
          notes: "Started exercises"
        },
        tenant: tenant,
        actor: user,
        authorize?: false
      )

    assert plan.status == :draft
    assert entry.entry_type == :lesson
    assert Decimal.equal?(log.taught_hours, Decimal.new("3"))
  end

  test "creates an APC lesson structure from a progression entry", %{tenant: tenant, user: user} do
    academic_year = Ash.Generator.generate(academic_year(tenant: tenant, actor: user))
    level_option = Ash.Generator.generate(level_option(tenant: tenant, actor: user))
    subject = Ash.Generator.generate(subject(tenant: tenant, actor: user))

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
        tenant: tenant,
        actor: user,
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
          teacher_id: user.id,
          weekly_hours: Decimal.new("4"),
          annual_hours: Decimal.new("96")
        },
        tenant: tenant,
        actor: user,
        authorize?: false
      )

    entry =
      Ash.create!(
        TeacherAssistant.Academics.ProgressionEntry,
        %{
          progression_plan_id: plan.id,
          week_number: 1,
          title: "Linear equations",
          planned_content: "Solving first-degree equations",
          planned_hours: Decimal.new("4")
        },
        tenant: tenant,
        actor: user,
        authorize?: false
      )

    lesson =
      Ash.create!(
        TeacherAssistant.Academics.ApcLessonPlan,
        %{
          progression_entry_id: entry.id,
          competence: "Solve a real-life problem using first-degree equations",
          situation_problem: "A market purchase with unknown unit price",
          learning_activities: "Observe, model, solve, verify",
          evaluation: "Individual equation exercise",
          remediation: "Guided correction for balancing equations",
          duration_minutes: 55
        },
        tenant: tenant,
        actor: user,
        authorize?: false
      )

    assert lesson.duration_minutes == 55
    assert lesson.competence =~ "Solve"
  end
end
