defmodule TeacherAssistant.Academics.ClassroomStudentAccessTest do
  use TeacherAssistant.DataCase, async: true

  describe "classroom access status" do
    test "defaults to allowed and can be suspended", %{tenant: tenant} do
      user = Ash.Generator.generate(admin_user(tenant: tenant))
      academic_year = Ash.Generator.generate(academic_year(tenant: tenant, actor: user))
      level_option = Ash.Generator.generate(level_option(tenant: tenant, actor: user))

      academic_year =
        TeacherAssistant.Academics.manage_classrooms!(
          academic_year,
          %{levels_options: [level_option.id]},
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      [classroom] = academic_year.classrooms
      student = Ash.Generator.generate(student(tenant: tenant, actor: user))

      enrollment =
        Ash.create!(
          TeacherAssistant.Academics.ClassroomStudent,
          %{
            classroom_id: classroom.id,
            student_id: student.id
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      assert enrollment.access_status == :allowed

      suspended =
        enrollment
        |> Ash.Changeset.for_update(
          :set_access_status,
          %{
            access_status: :suspended,
            access_note: "Fees pending",
            access_set_by_id: user.id
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )
        |> Ash.update!()

      assert suspended.access_status == :suspended
      assert suspended.access_note == "Fees pending"
      assert suspended.access_set_by_id == user.id
      assert %DateTime{} = suspended.access_set_at
    end
  end
end
