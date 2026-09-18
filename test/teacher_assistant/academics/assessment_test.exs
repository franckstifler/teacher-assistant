defmodule TeacherAssistant.Academics.AssessmentTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Organization.build_default_calendar(year)
    seq = Organization.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, ctx: ctx, cg: cg, seq: seq}
  end

  test "links a class group to a teaching context", %{ctx: ctx, cg: cg} do
    {:ok, ctx2} = Academics.link_class_group(ctx, cg)
    assert ctx2.class_group_id == cg.id
  end

  test "creates an assessment with defaults", %{ctx: ctx, seq: seq} do
    {:ok, a} = Assessment.create_assessment(ctx, seq, %{label: "Devoir 1"})
    assert a.label == "Devoir 1"
    assert Decimal.equal?(a.weight, Decimal.new(1))
    assert Decimal.equal?(a.max_score, Decimal.new(20))
    assert a.teaching_context_id == ctx.id
    assert a.sequence_id == seq.id
  end

  test "lists assessments for a context + sequence", %{ctx: ctx, seq: seq} do
    {:ok, _} = Assessment.create_assessment(ctx, seq, %{label: "Devoir 1"})
    {:ok, _} = Assessment.create_assessment(ctx, seq, %{label: "Devoir 2"})
    assert length(Assessment.list_assessments(ctx, seq)) == 2
  end

  test "fetch_owned_assessment refuses another workspace", %{ws: ws, ctx: ctx, seq: seq} do
    {:ok, a} = Assessment.create_assessment(ctx, seq, %{label: "Devoir 1"})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Assessment.fetch_owned_assessment(a.id, other)
    assert {:ok, %{id: id}} = Assessment.fetch_owned_assessment(a.id, ws)
    assert id == a.id
  end
end
