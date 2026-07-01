defmodule TeacherAssistant.Academics.MarkTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    {:ok, s1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    %{ctx: ctx, seq: seq, a: a, s1: s1, s2: s2}
  end

  test "upsert creates marks", %{a: a, s1: s1, s2: s2} do
    :ok =
      Academics.upsert_marks(a, [
        %{student_id: s1.id, score: Decimal.new("15")},
        %{student_id: s2.id, score: Decimal.new("9")}
      ])

    scores =
      Academics.list_marks(a)
      |> Map.new(fn m -> {m.student_id, m.score} end)

    assert Decimal.equal?(scores[s1.id], Decimal.new("15"))
    assert Decimal.equal?(scores[s2.id], Decimal.new("9"))
  end

  test "upsert updates an existing mark (no duplicate)", %{a: a, s1: s1} do
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("18")}])
    assert [m] = Academics.list_marks(a)
    assert Decimal.equal?(m.score, Decimal.new("18"))
  end

  test "nil score records absent", %{a: a, s1: s1} do
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: nil}])
    assert [m] = Academics.list_marks(a)
    assert m.score == nil
  end

  test "list_marks_for_context_sequence spans assessments", %{ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, a2} = Academics.create_assessment(ctx, seq, %{label: "Devoir 2"})
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])
    :ok = Academics.upsert_marks(a2, [%{student_id: s1.id, score: Decimal.new("11")}])
    assert length(Academics.list_marks_for_context_sequence(ctx, seq)) == 2
  end
end
