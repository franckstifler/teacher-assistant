defmodule TeacherAssistant.Academics.AssignmentGridTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.AssignmentGrid

  defp cg(id, level, pp \\ nil),
    do: %{id: id, subsystem: :francophone, level: level, serie: nil, form_master_user_id: pp}

  defp tc(id, cg, subject, teacher, hours, combined \\ nil),
    do: %{
      id: id,
      class_group_id: cg,
      subject_id: subject,
      teacher_user_id: teacher,
      weekly_hours: hours,
      combined_course_id: combined
    }

  setup do
    input = %{
      classes: [cg("6a", "6ème", "u1"), cg("6b", "6ème"), cg("x", "Libre")],
      subjects: [%{id: "maths"}, %{id: "svt"}, %{id: "eps"}],
      cells: %{{"maths", :francophone, "6ème", nil} => 1, {"svt", :francophone, "6ème", nil} => 1},
      contexts: [
        tc("t1", "6a", "maths", "u1", 5),
        tc("t2", "6a", "svt", "u2", 3, "cc"),
        tc("t3", "6b", "svt", "u2", 3, "cc"),
        tc("t4", "x", "eps", "u2", 2)
      ],
      school_hours: 18,
      services: %{"u2" => 4}
    }

    %{input: input}
  end

  test "cells: assigned, to assign from the coefficient grid, not taught", %{input: input} do
    g = AssignmentGrid.build(input)
    assert %{kind: :assigned, teacher_id: "u1"} = g.cells[{"6a", "maths"}]
    assert %{kind: :to_assign} = g.cells[{"6b", "maths"}]
    assert %{kind: :not_taught} = g.cells[{"6a", "eps"}]
    # a class off the grid only shows what is assigned
    assert %{kind: :not_taught} = g.cells[{"x", "maths"}]
    assert %{kind: :assigned} = g.cells[{"x", "eps"}]
    assert g.to_assign == 1
    assert g.without_pp == 2
    assert Enum.map(g.subjects, & &1.id) == ["maths", "svt", "eps"]
  end

  test "loads count a combined course once and use each teacher's own service", %{input: input} do
    g = AssignmentGrid.build(input)
    assert %{load: 5, service: 18, over?: false} = g.loads["u1"]
    # svt combined (3) once + eps (2) = 5 > own service 4
    assert %{load: 5, service: 4, over?: true} = g.loads["u2"]
    assert %{kind: :assigned, over?: true, combined?: true} = g.cells[{"6a", "svt"}]
  end

  test "load after a change does not double-count the current holder", %{input: input} do
    g = AssignmentGrid.build(input)
    assert AssignmentGrid.load_after(g, "u1", 5, "u1") == 5
    assert AssignmentGrid.load_after(g, "u2", 5, "u1") == 10
    assert AssignmentGrid.load_after(g, "u9", 4, nil) == 4
    assert AssignmentGrid.service(g, "u9") == 18
  end

  test "subjects with no assigned or to-assign cell are dropped", %{input: input} do
    g =
      AssignmentGrid.build(%{
        input
        | contexts: [],
          cells: %{{"maths", :francophone, "6ème", nil} => 1}
      })

    assert Enum.map(g.subjects, & &1.id) == ["maths"]
  end
end
