defmodule TeacherAssistant.Academics.AssessmentTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    seq = Organization.list_sequences(scope, year) |> List.first()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, year: year, ctx: ctx, cg: cg, seq: seq, scope: scope}
  end

  test "creates a context already assigned to the given class group", %{
    year: year,
    cg: cg,
    scope: scope
  } do
    ctx2 =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Physique",
        level: "3ème",
        class_group: cg
      })

    assert ctx2.class_group_id == cg.id
  end

  test "creates an assessment with defaults", %{ctx: ctx, seq: seq, scope: scope} do
    {:ok, a} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 1"})
    assert a.label == "Devoir 1"
    assert Decimal.equal?(a.weight, Decimal.new(1))
    assert Decimal.equal?(a.max_score, Decimal.new(20))
    assert a.teaching_context_id == ctx.id
    assert a.sequence_id == seq.id
  end

  test "lists assessments for a context + sequence", %{ctx: ctx, seq: seq, scope: scope} do
    {:ok, _} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 1"})
    {:ok, _} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 2"})
    assert length(Assessment.list_assessments(scope, ctx, seq)) == 2
  end

  test "fetch_owned_assessment refuses another workspace", %{ctx: ctx, seq: seq, scope: scope} do
    {:ok, a} = Assessment.create_assessment(scope, ctx, seq, %{label: "Devoir 1"})
    %{scope: other_scope} = TeacherFixtures.school_fixture()
    assert {:error, :not_found} = Assessment.fetch_owned_assessment(other_scope, a.id)
    assert {:ok, %{id: id}} = Assessment.fetch_owned_assessment(scope, a.id)
    assert id == a.id
  end
end
