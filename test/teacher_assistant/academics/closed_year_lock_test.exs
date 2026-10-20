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

  alias TeacherAssistant.Academics.{Reference, SanctionEntry, Student}

  # The year is closed by each test (`close/1`), after the records it needs exist.
  setup do
    world = MarksFixtures.marks_world()
    [%{enrollment: e} | _] = Enrollment.list_roster(world.head, world.cg)

    :ok =
      Assessment.upsert_marks(world.t, world.a, [
        %{student_id: world.s1.id, score: Decimal.new(12)}
      ])

    Map.put(world, :enrollment, e)
  end

  defp close(ctx), do: TeacherFixtures.close_year!(ctx.head, ctx.year)

  defp mark_of(ctx, student) do
    ctx.head |> Assessment.list_marks(ctx.a) |> Enum.find(&(&1.student_id == student.id))
  end

  # A pending correction on s1's mark, requested while the séquence is locked.
  defp pending_correction!(ctx) do
    MarksFixtures.lock!(ctx, Date.add(Reference.today(), -1))

    {:ok, correction} =
      Assessment.request_correction(ctx.t, %{
        assessment_id: ctx.a.id,
        student_id: ctx.s1.id,
        requested_status: :graded,
        requested_score: Decimal.new(14),
        motive: :erreur_saisie
      })

    correction
  end

  defp closed_error?({:error, error}) when is_exception(error),
    do: Exception.message(error) =~ "est clôturée"

  defp closed_error?({:error, error}), do: inspect(error) =~ "clôturée"
  defp closed_error?(_), do: false

  test "marks, assessments and council decisions of a closed year are refused", ctx do
    close(ctx)

    assert {:error, _} =
             Assessment.upsert_marks(ctx.t, ctx.a, [
               %{student_id: ctx.s1.id, score: Decimal.new(15)}
             ])

    assert {:error, _} =
             Assessment.upsert_marks(ctx.t, ctx.a, [
               %{student_id: ctx.s2.id, score: Decimal.new(15)}
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
    close(ctx)
    sanctions = fn -> SanctionEntry |> Ash.count!(scope: ctx.head) end
    before = sanctions.()

    # `Discipline.add_sanction/3` flattens a non-forbidden failure to `:sanction_failed`.
    assert {:error, _} =
             Discipline.add_sanction(ctx.head, ctx.enrollment, %{
               type: :avertissement,
               date: ~D[2025-09-10]
             })

    assert sanctions.() == before

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
    close(ctx)
    students = fn -> Student |> Ash.Query.filter(true) |> Ash.count!(scope: ctx.head) end
    before = students.()

    assert {:error, _} = Enrollment.add_student(ctx.head, ctx.cg, %{full_name: "Zoé", sex: :f})
    assert students.() == before
  end

  test "an enrolment of the open year cannot be moved into a class of a closed year", ctx do
    %{closed: closed, next: next} = close(ctx)
    [closed_cg | _] = Enrollment.list_class_groups(ctx.head, closed)
    [next_cg | _] = Enrollment.list_class_groups(ctx.head, next)
    {:ok, student} = Enrollment.add_student(ctx.head, next_cg, %{full_name: "Zoé", sex: :f})

    enrollment =
      ctx.head
      |> Enrollment.list_roster(next_cg)
      |> Enum.find(&(&1.student.id == student.id))
      |> Map.fetch!(:enrollment)

    assert closed_error?(
             enrollment
             |> Ash.Changeset.for_update(:update, %{class_group_id: closed_cg.id},
               scope: ctx.head
             )
             |> Ash.update()
           )
  end

  # Fees 1 (rule 8): nothing is recorded in a closed year; old debts carry over instead.
  test "a payment on a closed year's enrolment is refused", ctx do
    {:ok, _} = Fees.create_default_fee_types(ctx.head, ctx.year)
    close(ctx)

    assert {:error, _} =
             Fees.record_payment(ctx.head, ctx.enrollment, %{
               amount: 5_000,
               paid_on: ~D[2026-09-10],
               method: :cash
             })
  end

  test "an existing mark and assessment of a closed year can be neither changed nor deleted",
       ctx do
    mark = mark_of(ctx, ctx.s1)
    assert mark
    close(ctx)

    assert closed_error?(Ash.destroy(mark, scope: ctx.head))

    assert closed_error?(
             ctx.a
             |> Ash.Changeset.for_update(:update, %{label: "Renommée"}, scope: ctx.head)
             |> Ash.update()
           )

    assert closed_error?(Ash.destroy(ctx.a, scope: ctx.head))
    assert mark_of(ctx, ctx.s1)
  end

  test "correction requests and decisions of a closed year are refused", ctx do
    pending = pending_correction!(ctx)
    close(ctx)

    assert closed_error?(Assessment.approve_correction(ctx.head, pending))
    assert closed_error?(Assessment.refuse_correction(ctx.head, pending, "Non"))

    assert closed_error?(
             Assessment.request_correction(ctx.t, %{
               assessment_id: ctx.a.id,
               student_id: ctx.s2.id,
               requested_status: :absent,
               motive: :erreur_saisie
             })
           )

    assert Decimal.equal?(mark_of(ctx, ctx.s1).score, 12)
  end
end
