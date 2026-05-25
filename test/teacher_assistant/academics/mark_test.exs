defmodule TeacherAssistant.Academics.MarkTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  describe "marks" do
    test "save_mark updates the existing sequence mark and rejects out-of-range scores", %{
      tenant: tenant,
      user: user
    } do
      %{
        classroom: classroom,
        sequence: sequence,
        student: student,
        level_option_subject: level_option_subject
      } = mark_setup(tenant, user)

      first =
        TeacherAssistant.Academics.save_mark!(
          %{
            student_id: student.id,
            classroom_id: classroom.id,
            sequence_id: sequence.id,
            level_option_subject_id: level_option_subject.id,
            score: Decimal.new("12.50"),
            comment: "Initial"
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      second =
        TeacherAssistant.Academics.save_mark!(
          %{
            student_id: student.id,
            classroom_id: classroom.id,
            sequence_id: sequence.id,
            level_option_subject_id: level_option_subject.id,
            score: Decimal.new("16.00"),
            comment: "Updated"
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )

      student_id = student.id
      sequence_id = sequence.id
      level_option_subject_id = level_option_subject.id

      marks =
        TeacherAssistant.Academics.Mark
        |> Ash.Query.filter(
          student_id == ^student_id and
            sequence_id == ^sequence_id and
            level_option_subject_id == ^level_option_subject_id
        )
        |> Ash.read!(tenant: tenant, actor: user, authorize?: false)

      assert first.id == second.id
      assert [%{comment: "Updated"} = mark] = marks
      assert Decimal.equal?(mark.score, Decimal.new("16.00"))

      assert_raise Ash.Error.Invalid, fn ->
        TeacherAssistant.Academics.save_mark!(
          %{
            student_id: student.id,
            classroom_id: classroom.id,
            sequence_id: sequence.id,
            level_option_subject_id: level_option_subject.id,
            score: Decimal.new("21")
          },
          tenant: tenant,
          actor: user,
          authorize?: false
        )
      end
    end
  end

  defp mark_setup(tenant, user) do
    academic_year = Ash.Generator.generate(academic_year(tenant: tenant, actor: user))
    level_option = Ash.Generator.generate(level_option(tenant: tenant, actor: user))
    subject = Ash.Generator.generate(subject(tenant: tenant, actor: user))
    student = Ash.Generator.generate(student(tenant: tenant, actor: user))

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
    [term] = academic_year.terms

    sequence =
      Ash.create!(
        TeacherAssistant.Academics.Sequence,
        %{
          name: "Sequence 1",
          term_id: term.id,
          start_date: Date.utc_today(),
          end_date: Date.add(Date.utc_today(), 14)
        },
        tenant: tenant,
        actor: user,
        authorize?: false
      )

    %{
      classroom: classroom,
      sequence: sequence,
      student: student,
      level_option_subject: level_option_subject
    }
  end
end
