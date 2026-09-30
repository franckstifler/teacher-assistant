defmodule TeacherAssistant.Academics.MarkJournalTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.MarksFixtures

  setup do
    MarksFixtures.marks_world()
  end

  test "a save journals one row per changed mark, sharing a batch id", ctx do
    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [
        %{student_id: ctx.s1.id, score: Decimal.new(12)},
        %{student_id: ctx.s2.id, score: Decimal.new(9)}
      ])

    assert [e1, e2] = Assessment.list_mark_events(ctx.head)
    assert e1.batch_id && e1.batch_id == e2.batch_id
    assert e1.action == :saisie
    assert e1.actor_user_id == ctx.t.current_user.id
    assert e1.before_status == nil and e1.after_status == :graded
  end

  test "re-saving the same values journals nothing (12 == 12.0)", ctx do
    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(12)}])

    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new("12.0")}])

    assert length(Assessment.list_mark_events(ctx.head)) == 1
  end

  test "clearing a mark journals before -> blank", ctx do
    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(12)}])

    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: nil}])

    [latest | _] = Assessment.list_mark_events(ctx.head)
    assert latest.before_status == :graded and Decimal.equal?(latest.before_score, 12)
    assert latest.after_status == nil and latest.after_score == nil
  end

  test "an absence is journaled with its status", ctx do
    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, status: :absent}])
    assert [%{after_status: :absent, after_score: nil}] = Assessment.list_mark_events(ctx.head)
  end

  test "nobody records journal rows through the action; teachers cannot read it", ctx do
    assert_forbidden(
      TeacherAssistant.Academics.MarkEvent
      |> Ash.Changeset.for_create(
        :record,
        %{action: :saisie, assessment_id: ctx.a.id, student_id: ctx.s1.id},
        scope: ctx.head
      )
      |> Ash.create()
    )

    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(12)}])

    assert Assessment.list_mark_events(ctx.t) == []
  end
end
