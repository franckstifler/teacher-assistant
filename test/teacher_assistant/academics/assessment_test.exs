defmodule TeacherAssistant.Academics.AssessmentTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    seq = Organization.list_sequences(year) |> List.first()

    ctx =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, year: year, ctx: ctx, cg: cg, seq: seq}
  end

  test "creates a context already assigned to the given class group", %{
    ws: ws,
    year: year,
    cg: cg
  } do
    ctx2 =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        subject: "Physique",
        level: "3ème",
        class_group: cg
      })

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
    %{workspace: other} = TeacherFixtures.school_fixture()
    assert {:error, :not_found} = Assessment.fetch_owned_assessment(a.id, other)
    assert {:ok, %{id: id}} = Assessment.fetch_owned_assessment(a.id, ws)
    assert id == a.id
  end
end
