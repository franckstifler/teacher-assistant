defmodule TeacherAssistant.Academics.CoefficientResolutionTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.Academics.SubjectCoefficient
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

    {:ok, cg_c} =
      Enrollment.create_class_group(scope, year, %{label: "2nde C", level: "2nde", serie: "C"})

    {:ok, cg_a} =
      Enrollment.create_class_group(scope, year, %{label: "2nde A", level: "2nde", serie: "A4"})

    {:ok, musique} =
      Curriculum.create_subject(scope, %{name: "Musique", default_coefficient: Decimal.new(2)})

    blank = Curriculum.coefficient_cells(scope)[{musique.id, :francophone, "2nde", nil}]

    {:ok, _} =
      blank |> Ash.Changeset.for_update(:update, %{coefficient: 4}, scope: scope) |> Ash.update()

    %{scope: scope, head: head, cg_c: cg_c, cg_a: cg_a, musique: musique}
  end

  defp assign(scope, cg, head, subject) do
    {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: subject})
    [tc] = Curriculum.list_assignments_for_class(scope, cg)
    tc
  end

  defp put_cell(scope, subject, level, serie, coef) do
    {:ok, cell} =
      SubjectCoefficient
      |> Ash.Changeset.for_create(
        :create,
        %{
          subject_id: subject.id,
          subsystem: :francophone,
          level: level,
          serie: serie,
          coefficient: coef
        },
        scope: scope
      )
      |> Ash.create()

    cell
  end

  test "an assignment without override takes the grid value", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Musique")
    assert tc.subject_id == ctx.musique.id
    assert tc.coefficient == nil
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new(4))
    assert tc.taught_here?
  end

  test "a série cell beats the blank-série cell, for that série only", ctx do
    put_cell(ctx.scope, ctx.musique, "2nde", "C", 5)

    assert Decimal.equal?(
             assign(ctx.scope, ctx.cg_c, ctx.head, "Musique").effective_coefficient,
             5
           )

    assert Decimal.equal?(
             assign(ctx.scope, ctx.cg_a, ctx.head, "Musique").effective_coefficient,
             4
           )
  end

  test "a class override beats the grid, and clearing it returns to the grid", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Musique")
    {:ok, _} = Curriculum.set_assignment_coefficient(ctx.scope, tc, "6,5")
    [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg_c)
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new("6.5"))

    {:ok, _} = Curriculum.clear_assignment_coefficient(ctx.scope, tc)
    [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg_c)
    assert tc.coefficient == nil
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new(4))
  end

  test "without a cell the subject default applies and the assignment is flagged", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Musique")

    :ok =
      Ash.destroy(
        Curriculum.coefficient_cells(ctx.scope)[{ctx.musique.id, :francophone, "2nde", nil}],
        scope: ctx.scope
      )

    [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg_c)
    refute tc.taught_here?
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new(2))
    assert tc.id
  end

  test "only subjects taught at the class's level are offered", ctx do
    assert ctx.musique.id in Enum.map(Curriculum.subjects_taught_in(ctx.scope, ctx.cg_c), & &1.id)

    :ok =
      Ash.destroy(
        Curriculum.coefficient_cells(ctx.scope)[{ctx.musique.id, :francophone, "2nde", nil}],
        scope: ctx.scope
      )

    refute ctx.musique.id in Enum.map(Curriculum.subjects_taught_in(ctx.scope, ctx.cg_c), & &1.id)
  end

  test "assigning an unknown subject name creates it in the catalog", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Espagnol")

    assert %{name: "Espagnol"} =
             Enum.find(Curriculum.list_subjects(ctx.scope), &(&1.id == tc.subject_id))

    assert tc.subject == "Espagnol"
  end
end
