defmodule TeacherAssistant.Academics.SubjectExemptionsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "4e A", level: "4ème"})
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, zoe} = Enrollment.add_student(scope, other, %{full_name: "Zoé", sex: :f})
    {:ok, esp} = Curriculum.create_subject(scope, %{name: "Espagnol"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: esp})
    %{scope: scope, esp: esp, tc: tc, awa: awa, bob: bob, zoe: zoe}
  end

  defp make_optional(scope, subject, on?) do
    Curriculum.update_coefficient_grid(scope, %{"optional" => %{subject.id => to_string(on?)}})
  end

  test "only optional subjects accept exemptions", ctx do
    assert {:error, :not_optional} = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])
    assert :ok = make_optional(ctx.scope, ctx.esp, true)
    assert :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])
    assert Curriculum.exempt_student_ids(ctx.scope, ctx.tc) == MapSet.new([ctx.bob.id])

    assert :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id, ctx.bob.id])
    assert Curriculum.exempt_student_ids(ctx.scope, ctx.tc) == MapSet.new()
  end

  test "a student from another class is refused and nothing changes", ctx do
    :ok = make_optional(ctx.scope, ctx.esp, true)
    assert {:error, :unknown_student} = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.zoe.id])
    assert Curriculum.exempt_student_ids(ctx.scope, ctx.tc) == MapSet.new()
  end

  test "an optional subject with exemptions cannot be made compulsory again", ctx do
    :ok = make_optional(ctx.scope, ctx.esp, true)
    :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])

    assert {:error, {:invalid, errors}} = make_optional(ctx.scope, ctx.esp, false)
    assert errors[{:optional, ctx.esp.id}] == [{:has_exemptions, ["4e A"]}]
  end

  test "a teacher cannot change exemptions", ctx do
    :ok = make_optional(ctx.scope, ctx.esp, true)
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope)
    assert_forbidden(Curriculum.set_exemptions(teacher, ctx.tc, [ctx.awa.id]))
  end
end
