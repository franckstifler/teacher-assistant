defmodule TeacherAssistant.Academics.EntryGraceDaysTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Organization}
  alias TeacherAssistant.Academics.Reference

  setup do
    TeacherAssistant.MarksFixtures.marks_world()
  end

  test "a school starts with 5 grace days", ctx do
    [seq | _] = Organization.list_sequences(ctx.head, ctx.year)
    assert seq.grade_entry_deadline == Date.add(seq.end_date, 5)
  end

  test "the deadline uses the school's grace days", ctx do
    assert {:ok, %{entry_grace_days: 7}} = Assessment.update_entry_grace_days(ctx.head, "7")
    [seq | _] = Organization.list_sequences(ctx.head, ctx.year)
    assert seq.grade_entry_deadline == Date.add(seq.end_date, 7)
    # Every member sees the same deadline.
    [seq | _] = Organization.list_sequences(ctx.t, ctx.year)
    assert seq.grade_entry_deadline == Date.add(seq.end_date, 7)
  end

  test "grace days outside 0..30 or not a number are refused", ctx do
    assert {:error, _} = Assessment.update_entry_grace_days(ctx.head, "31")
    assert {:error, _} = Assessment.update_entry_grace_days(ctx.head, "-1")
    assert {:error, _} = Assessment.update_entry_grace_days(ctx.head, "abc")
    assert {:ok, %{entry_grace_days: 0}} = Assessment.update_entry_grace_days(ctx.head, "0")
  end

  test "a teacher cannot change grace days", ctx do
    assert {:error, _} = Assessment.update_entry_grace_days(ctx.t, "7")
  end

  test "Cameroon's date is UTC+1" do
    assert Reference.today(~U[2026-10-02 22:59:59Z]) == ~D[2026-10-02]
    assert Reference.today(~U[2026-10-02 23:00:00Z]) == ~D[2026-10-03]
  end
end
