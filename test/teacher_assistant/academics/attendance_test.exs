defmodule TeacherAssistant.Academics.AttendanceTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  describe "attendance records" do
    test "creating attendance for the same student, class, and date updates the existing row", %{
      tenant: tenant,
      user: user
    } do
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
      date = Date.utc_today()

      first =
        Ash.create!(
          TeacherAssistant.Academics.Attendance,
          %{
            student_id: student.id,
            classroom_id: classroom.id,
            date: date,
            status: :present,
            comment: "Arrived on time"
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      second =
        Ash.create!(
          TeacherAssistant.Academics.Attendance,
          %{
            student_id: student.id,
            classroom_id: classroom.id,
            date: date,
            status: :absent,
            comment: "Medical appointment"
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      student_id = student.id
      classroom_id = classroom.id

      attendances =
        TeacherAssistant.Academics.Attendance
        |> Ash.Query.filter(
          student_id == ^student_id and classroom_id == ^classroom_id and date == ^date
        )
        |> Ash.read!(tenant: tenant, actor: user, authorize?: false)

      assert first.id == second.id
      assert [%{status: :absent, comment: "Medical appointment"}] = attendances
    end
  end
end
