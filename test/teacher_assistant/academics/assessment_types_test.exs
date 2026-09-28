defmodule TeacherAssistant.Academics.AssessmentTypesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    %{scope: scope, seq: seq, tc: tc}
  end

  test "a school starts with the three usual types", %{scope: scope} do
    assert [
             {"Interrogation écrite", "0.5"},
             {"Devoir surveillé", "1"},
             {"Travaux pratiques", "0.5"}
           ] =
             Enum.map(
               Assessment.list_assessment_types(scope),
               &{&1.name, Decimal.to_string(Decimal.normalize(&1.default_weight), :normal)}
             )
  end

  test "an assessment of a type copies its weight; changing the type later does not", ctx do
    [ie | _] = Assessment.list_assessment_types(ctx.scope)

    {:ok, a} =
      Assessment.create_assessment(ctx.scope, ctx.tc, ctx.seq, %{
        label: "IE 1",
        assessment_type_id: ie.id
      })

    assert Decimal.equal?(a.weight, Decimal.new("0.5"))

    {:ok, _} = Assessment.update_assessment_type(ctx.scope, ie, %{default_weight: Decimal.new(2)})
    {:ok, reloaded} = Assessment.fetch_owned_assessment(ctx.scope, a.id)
    assert Decimal.equal?(reloaded.weight, Decimal.new("0.5"))
  end

  test "the school's default maximum applies when none is given", ctx do
    {:ok, _} = Assessment.update_default_max_score(ctx.scope, "10")
    {:ok, a} = Assessment.create_assessment(ctx.scope, ctx.tc, ctx.seq, %{label: "Quiz"})
    assert Decimal.equal?(a.max_score, 10)
  end

  test "a used type cannot be deleted; an unused one can", ctx do
    [ie, ds | _] = Assessment.list_assessment_types(ctx.scope)

    {:ok, _} =
      Assessment.create_assessment(ctx.scope, ctx.tc, ctx.seq, %{
        label: "IE 1",
        assessment_type_id: ie.id
      })

    assert {:error, :in_use} = Assessment.delete_assessment_type(ctx.scope, ie)
    assert :ok = Assessment.delete_assessment_type(ctx.scope, ds)
  end

  test "a type weight must be positive; teachers cannot manage types", %{scope: scope} do
    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.create_assessment_type(scope, %{
               name: "Oral",
               default_weight: Decimal.new(0)
             })

    teacher = TeacherFixtures.member_scope_fixture(scope)

    assert_forbidden(
      Assessment.create_assessment_type(teacher, %{name: "Oral", default_weight: Decimal.new(1)})
    )
  end
end
