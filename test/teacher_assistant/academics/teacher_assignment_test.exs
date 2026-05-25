defmodule TeacherAssistant.Academics.TeacherAssignmentTest do
  use TeacherAssistant.DataCase, async: true

  test "list_teacher_classrooms returns only classrooms assigned to the teacher", %{
    tenant: tenant,
    user: admin
  } do
    academic_year = Ash.Generator.generate(academic_year(tenant: tenant, actor: admin))
    level_option = Ash.Generator.generate(level_option(tenant: tenant, actor: admin))
    subject = Ash.Generator.generate(subject(tenant: tenant, actor: admin))
    assigned_teacher = Ash.Generator.generate(user(tenant: tenant))
    other_teacher = Ash.Generator.generate(user(tenant: tenant))

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
        actor: admin,
        authorize?: false
      )

    [classroom] = academic_year.classrooms

    Ash.create!(
      TeacherAssistant.Academics.TeachingAssignment,
      %{
        classroom_id: classroom.id,
        level_option_subject_id: level_option_subject.id,
        teacher_id: assigned_teacher.id
      },
      tenant: tenant,
      actor: admin,
      authorize?: false
    )

    assert [teacher_classroom] =
             TeacherAssistant.Academics.list_teacher_classrooms!(
               academic_year.id,
               assigned_teacher.id,
               tenant: tenant,
               actor: assigned_teacher,
               authorize?: false
             )

    assert teacher_classroom.id == classroom.id

    assert [] =
             TeacherAssistant.Academics.list_teacher_classrooms!(
               academic_year.id,
               other_teacher.id,
               tenant: tenant,
               actor: other_teacher,
               authorize?: false
             )
  end
end
