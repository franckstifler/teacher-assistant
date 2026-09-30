defmodule TeacherAssistant.Academics.MarkLockTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment}
  alias TeacherAssistant.Academics.{Lock, Mark, Reference, Sequence}
  import TeacherAssistant.MarksFixtures, only: [lock!: 2]

  setup do
    TeacherAssistant.MarksFixtures.marks_world()
  end

  test "the deadline day is open, the day after is locked" do
    seq = %Sequence{grade_entry_deadline: ~D[2026-10-02]}
    refute Lock.locked?(seq, ~D[2026-10-02])
    assert Lock.locked?(seq, ~D[2026-10-03])
  end

  test "tests run on a fixed school clock" do
    assert Reference.today() == ~D[2025-09-15]
  end

  test "marks save on the deadline day itself", ctx do
    lock!(ctx, Reference.today())

    assert :ok =
             Assessment.upsert_marks(ctx.t, ctx.a, [
               %{student_id: ctx.s1.id, score: Decimal.new(10)}
             ])
  end

  test "nobody saves, clears or deletes marks of a locked assessment", ctx do
    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(12)}])

    lock!(ctx, Date.add(Reference.today(), -1))

    for scope <- [ctx.t, ctx.head] do
      assert {:error, _} =
               Assessment.upsert_marks(scope, ctx.a, [
                 %{student_id: ctx.s2.id, score: Decimal.new(10)}
               ])

      assert {:error, _} =
               Assessment.upsert_marks(scope, ctx.a, [%{student_id: ctx.s1.id, score: nil}])
    end

    [mark] = Assessment.list_marks(ctx.head, ctx.a)

    assert {:error, e1} =
             mark
             |> Ash.Changeset.for_update(:update, %{score: 3}, scope: ctx.head)
             |> Ash.update()

    assert {:error, e2} = Ash.destroy(mark, scope: ctx.head)
    for e <- [e1, e2], do: assert(Exception.message(e) =~ "locked")
    assert [%Mark{}] = Assessment.list_marks(ctx.head, ctx.a)
  end

  test "a combined save with one locked class writes nothing", ctx do
    {:ok, cg2} =
      Enrollment.create_class_group(ctx.head, ctx.year, %{label: "6e Z", level: "6ème"})

    {:ok, s3} = Enrollment.add_student(ctx.head, cg2, %{full_name: "Chloé", sex: :f})
    {:ok, tc2} = Curriculum.assign_teacher(ctx.head, cg2, ctx.t.current_user, %{subject: "Maths"})
    [_, seq2 | _] = TeacherAssistant.Organization.list_sequences(ctx.head, ctx.year)
    {:ok, open_a} = Assessment.create_assessment(ctx.t, tc2, seq2, %{label: "D"})
    lock!(ctx, Date.add(Reference.today(), -1))

    assert {:error, _} =
             Assessment.upsert_marks_all_or_nothing(ctx.t, [
               {open_a, [%{student_id: s3.id, score: Decimal.new(10)}]},
               {ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(10)}]}
             ])

    assert Assessment.list_marks(ctx.head, open_a) == []
  end

  test "assessments of a locked séquence cannot be created, edited or deleted", ctx do
    lock!(ctx, Date.add(Reference.today(), -1))

    seq =
      Enum.find(
        TeacherAssistant.Organization.list_sequences(ctx.head, ctx.year),
        &(&1.id == ctx.seq.id)
      )

    assert {:error, e1} = Assessment.create_assessment(ctx.t, ctx.tc, seq, %{label: "D2"})

    assert {:error, e2} =
             ctx.a
             |> Ash.Changeset.for_update(:update, %{label: "X"}, scope: ctx.head)
             |> Ash.update()

    assert {:error, e3} = Ash.destroy(ctx.a, scope: ctx.head)
    for e <- [e1, e2, e3], do: assert(Exception.message(e) =~ "locked")
  end

  test "an open assessment is still edited and deleted", ctx do
    assert {:ok, _} =
             ctx.a
             |> Ash.Changeset.for_update(:update, %{label: "X"}, scope: ctx.head)
             |> Ash.update()

    assert :ok = Ash.destroy(ctx.a, scope: ctx.head)
  end
end
