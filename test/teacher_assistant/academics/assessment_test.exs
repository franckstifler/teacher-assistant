defmodule TeacherAssistant.Academics.AssessmentTest do
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
    %{ws: ws, ctx: ctx, cg: cg, seq: seq}
  end

  test "links a class group to a teaching context", %{ctx: ctx, cg: cg} do
    {:ok, ctx2} = Academics.link_class_group(ctx, cg)
    assert ctx2.class_group_id == cg.id
  end

  test "creates an assessment with defaults", %{ctx: ctx, seq: seq} do
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    assert a.label == "Devoir 1"
    assert Decimal.equal?(a.weight, Decimal.new(1))
    assert Decimal.equal?(a.max_score, Decimal.new(20))
    assert a.teaching_context_id == ctx.id
    assert a.sequence_id == seq.id
  end

  test "lists assessments for a context + sequence", %{ctx: ctx, seq: seq} do
    {:ok, _} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    {:ok, _} = Academics.create_assessment(ctx, seq, %{label: "Devoir 2"})
    assert length(Academics.list_assessments(ctx, seq)) == 2
  end

  test "fetch_owned_assessment refuses another workspace", %{ws: ws, ctx: ctx, seq: seq} do
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Academics.fetch_owned_assessment(a.id, other)
    assert {:ok, %{id: id}} = Academics.fetch_owned_assessment(a.id, ws)
    assert id == a.id
  end
end
