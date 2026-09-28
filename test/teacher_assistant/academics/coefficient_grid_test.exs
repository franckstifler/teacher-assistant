defmodule TeacherAssistant.Academics.CoefficientGridTest do
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

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "2nde C", level: "2nde", serie: "C"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))
    %{scope: scope, head: head, cg: cg, maths: maths}
  end

  defp tok(level, serie \\ nil), do: Curriculum.cell_token({:francophone, level, serie})

  test "the layout lists the school's levels and the séries its classes use", %{scope: scope} do
    [%{subsystem: :francophone, levels: levels, series: series}] = Curriculum.coefficient_grid_layout(scope)
    assert %{level: "2nde", streamed?: true} in levels
    assert %{level: "6ème", streamed?: false} in levels
    assert series == ["C"]
  end

  test "saves values, a new série cell, a cleared cell and a group", %{scope: scope, maths: m} do
    params = %{
      "cells" => %{m.id => %{tok("2nde") => "3,5", tok("2nde", "C") => "5", tok("6ème") => ""}},
      "groups" => %{m.id => "g1_lettres"}
    }

    assert :ok = Curriculum.update_coefficient_grid(scope, params)
    cells = Curriculum.coefficient_cells(scope)
    assert Decimal.equal?(cells[{m.id, :francophone, "2nde", nil}].coefficient, Decimal.new("3.5"))
    assert Decimal.equal?(cells[{m.id, :francophone, "2nde", "C"}].coefficient, 5)
    refute Map.has_key?(cells, {m.id, :francophone, "6ème", nil})
    assert Enum.find(Curriculum.list_subjects(scope), &(&1.id == m.id)).bulletin_group == :g1_lettres
  end

  test "an invalid value writes nothing", %{scope: scope, maths: m} do
    params = %{"cells" => %{m.id => %{tok("2nde") => "3", tok("1ère") => "abc"}}}
    assert {:error, {:invalid, errors}} = Curriculum.update_coefficient_grid(scope, params)
    assert errors[{m.id, :francophone, "1ère", nil}] == [:invalid_coefficient]
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", nil}].coefficient, 4)
  end

  test "a cell used by a class cannot be cleared", %{scope: scope, head: head, cg: cg, maths: m} do
    {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: m})
    params = %{"cells" => %{m.id => %{tok("2nde") => ""}}}
    assert {:error, {:invalid, errors}} = Curriculum.update_coefficient_grid(scope, params)
    assert errors[{m.id, :francophone, "2nde", nil}] == [{:in_use, ["2nde C"]}]
  end

  test "unknown subsystems and foreign subjects are ignored", %{scope: scope, maths: m} do
    params = %{
      "cells" => %{
        m.id => %{"martian|2nde|" => "9"},
        Ecto.UUID.generate() => %{tok("2nde") => "9"}
      }
    }

    assert :ok = Curriculum.update_coefficient_grid(scope, params)
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", nil}].coefficient, 4)
  end

  test "a teacher cannot change the grid", %{scope: scope, maths: m} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    params = %{"cells" => %{m.id => %{tok("2nde") => "9", tok("1ère") => "9"}}}
    assert_forbidden(Curriculum.update_coefficient_grid(teacher, params))
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "1ère", nil}].coefficient, 4)
  end
end
