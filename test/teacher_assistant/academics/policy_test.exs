defmodule TeacherAssistant.Academics.PolicyTest do
  use TeacherAssistant.DataCase, async: true

  describe "configuration policies" do
    test "admins manage configuration while teachers only read", %{tenant: tenant} do
      admin = Ash.Generator.generate(admin_user(tenant: tenant))
      teacher = Ash.Generator.generate(user(tenant: tenant))
      level = Ash.Generator.generate(level(tenant: tenant, actor: admin))

      assert TeacherAssistant.Academics.can_read_levels?(teacher, tenant: tenant, data: level)
      assert TeacherAssistant.Academics.can_create_level?(admin, tenant: tenant)
      refute TeacherAssistant.Academics.can_create_level?(teacher, tenant: tenant)
      refute TeacherAssistant.Academics.can_update_level?(teacher, level, tenant: tenant)
      refute TeacherAssistant.Academics.can_destroy_level?(teacher, level, tenant: tenant)
    end
  end

  describe "teacher workflow policies" do
    test "teachers can save marks and attendance, but cannot change classroom access", %{
      tenant: tenant
    } do
      admin = Ash.Generator.generate(admin_user(tenant: tenant))
      teacher = Ash.Generator.generate(user(tenant: tenant))
      enrollment = classroom_enrollment(tenant, admin)

      assert Ash.can?({TeacherAssistant.Academics.Mark, :create}, teacher, tenant: tenant)
      assert Ash.can?({TeacherAssistant.Academics.Attendance, :create}, teacher, tenant: tenant)

      refute Ash.can?({enrollment, :set_access_status}, teacher, tenant: tenant)
      assert Ash.can?({enrollment, :set_access_status}, admin, tenant: tenant)
    end
  end

  describe "programme progression policies" do
    test "teachers create logs and vice principals read progression", %{tenant: tenant} do
      teacher = Ash.Generator.generate(user(tenant: tenant))
      vice_principal = Ash.Generator.generate(user(tenant: tenant, role: :vice_principal))

      assert Ash.can?({TeacherAssistant.Academics.TeachingLog, :create}, teacher, tenant: tenant)

      assert Ash.can?({TeacherAssistant.Academics.ProgressionPlan, :read}, vice_principal,
               tenant: tenant
             )

      refute Ash.can?({TeacherAssistant.Academics.ProgressionPlan, :destroy}, teacher,
               tenant: tenant
             )
    end
  end

  defp classroom_enrollment(tenant, actor) do
    academic_year = Ash.Generator.generate(academic_year(tenant: tenant, actor: actor))
    level_option = Ash.Generator.generate(level_option(tenant: tenant, actor: actor))

    academic_year =
      TeacherAssistant.Academics.manage_classrooms!(
        academic_year,
        %{levels_options: [level_option.id]},
        tenant: tenant,
        actor: actor,
        authorize?: false
      )

    [classroom] = academic_year.classrooms
    student = Ash.Generator.generate(student(tenant: tenant, actor: actor))

    Ash.create!(
      TeacherAssistant.Academics.ClassroomStudent,
      %{classroom_id: classroom.id, student_id: student.id},
      tenant: tenant,
      actor: actor,
      authorize?: false
    )
  end
end
