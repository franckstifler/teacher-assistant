defmodule TeacherAssistant.Academics.NewYearPlanTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.NewYearPlan

  defp cls(id, label, level, serie \\ nil),
    do: %{id: id, label: label, level: level, serie: serie}

  test "the suffix is the label's last word when it is letters or a number" do
    assert NewYearPlan.suffix(cls("a", "6ème A", "6ème")) == "A"
    assert NewYearPlan.suffix(cls("a", "3e 2", "3ème")) == "2"
    assert NewYearPlan.suffix(cls("a", "6ème", "6ème")) == nil
    assert NewYearPlan.suffix(cls("a", "2nde C", "2nde", "C")) == nil
    assert NewYearPlan.suffix(cls("a", "2nde C B", "2nde", "C")) == "B"
  end

  test "the admis target is the next level's class with the same suffix and série" do
    classes = [
      cls("6a", "6ème A", "6ème"),
      cls("6b", "6ème B", "6ème"),
      cls("5a", "5ème A", "5ème"),
      cls("3", "3ème", "3ème"),
      cls("2c", "2nde C", "2nde", "C"),
      cls("1c", "1ère C", "1ère", "C"),
      cls("tc", "Terminale C", "Terminale", "C")
    ]

    targets = NewYearPlan.default_targets(classes)
    assert targets["6a"] == "5a"
    # No « 5ème B »: the admin chooses.
    assert targets["6b"] == nil
    # 3ème has no série, every 2nde has one.
    assert targets["3"] == nil
    assert targets["2c"] == "1c"
    # Last level.
    assert targets["tc"] == nil
  end

  test "levels the school does not have are skipped to the next one it has" do
    classes = [cls("3", "3ème A", "3ème"), cls("2", "2nde A", "2nde")]
    assert NewYearPlan.default_targets(classes)["3"] == "2"
  end

  test "the next year's name follows the old one" do
    assert NewYearPlan.next_name("2025-2026") == "2026-2027"
    assert NewYearPlan.next_name(" 2025 / 2026 ") == "2026-2027"
    assert NewYearPlan.next_name("Année de référence") == ""
  end

  test "each decision places the student, and the totals count them" do
    students = [
      %{student_id: "awa", enrollment_id: "e1", class_id: "6a", decision: :admis},
      %{student_id: "bob", enrollment_id: "e2", class_id: "6a", decision: :redouble},
      %{student_id: "cy", enrollment_id: "e3", class_id: "6a", decision: :admis_rachat},
      %{student_id: "dan", enrollment_id: "e4", class_id: "6a", decision: :exclu},
      %{student_id: "eve", enrollment_id: "e5", class_id: "6a", decision: nil},
      %{student_id: "fay", enrollment_id: "e6", class_id: "tc", decision: :admis}
    ]

    placed = NewYearPlan.placements(students, %{"6a" => "5a", "tc" => nil})
    by = Map.new(placed, &{&1.student_id, &1})

    assert %{to: "5a", repeater?: false, reason: nil} = by["awa"]
    assert %{to: "6a", repeater?: true} = by["bob"]
    assert %{to: "5a"} = by["cy"]
    assert %{to: nil, reason: :exclu} = by["dan"]
    assert %{to: nil, reason: :sans_decision} = by["eve"]
    assert %{to: nil, reason: :sans_classe} = by["fay"]

    assert NewYearPlan.sizes(placed) == %{"5a" => 2, "6a" => 1}

    assert NewYearPlan.totals(placed) == %{
             reenrolled: 3,
             repeaters: 1,
             not_reenrolled: %{exclu: 1, sans_decision: 1, sans_classe: 1}
           }
  end
end
