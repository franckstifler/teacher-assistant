defmodule TeacherAssistant.Academics.ClosedYearLockTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.{
    Assessment,
    Councils,
    Curriculum,
    Discipline,
    Enrollment,
    Fees,
    MarksFixtures,
    Organization,
    TeacherFixtures
  }

  alias TeacherAssistant.Academics.Student

  setup do
    world = MarksFixtures.marks_world()
    [%{enrollment: e} | _] = Enrollment.list_roster(world.head, world.cg)
    TeacherFixtures.close_year!(world.head, world.year)
    Map.put(world, :enrollment, e)
  end

  defp closed_error?({:error, error}) when is_exception(error),
    do: Exception.message(error) =~ "est clôturée"

  defp closed_error?({:error, error}), do: inspect(error) =~ "clôturée"
  defp closed_error?(_), do: false

  test "marks, assessments and council decisions of a closed year are refused", ctx do
    assert {:error, _} =
             Assessment.upsert_marks(ctx.t, ctx.a, [
               %{student_id: ctx.s1.id, score: Decimal.new(15)}
             ])

    assert closed_error?(
             Assessment.create_assessment(ctx.t, ctx.tc, ctx.seq, %{label: "Interro 2"})
           )

    assert closed_error?(
             Councils.set_decision(ctx.head, ctx.cg, {:annual, ctx.year}, ctx.s1.id, %{
               "passage_decision" => "admis"
             })
           )
  end

  test "school life, courses and the calendar of a closed year are refused", ctx do
    # `Discipline.add_sanction/3` flattens a non-forbidden failure to `:sanction_failed`.
    assert {:error, _} =
             Discipline.add_sanction(ctx.head, ctx.enrollment, %{
               type: :avertissement,
               date: ~D[2025-09-10]
             })

    assert closed_error?(
             Curriculum.assign_teacher(ctx.head, ctx.cg, ctx.head.current_user, %{subject: "SVT"})
           )

    assert closed_error?(
             Organization.create_holiday(ctx.head, ctx.year, %{
               label: "Pont",
               start_date: ~D[2025-12-19],
               end_date: ~D[2025-12-20]
             })
           )
  end

  test "enrolling into a closed year writes nothing at all", ctx do
    students = fn -> Student |> Ash.Query.filter(true) |> Ash.count!(scope: ctx.head) end
    before = students.()

    assert {:error, _} = Enrollment.add_student(ctx.head, ctx.cg, %{full_name: "Zoé", sex: :f})
    assert students.() == before
  end

  test "a payment on a closed year's enrolment is still recorded (arrears)", ctx do
    assert {:ok, _} =
             Fees.record_payment(ctx.head, ctx.enrollment, %{
               amount: 5_000,
               paid_on: ~D[2026-09-10],
               method: :cash
             })
  end
end
