defmodule TeacherAssistant.Academics.ModuleGroupingTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.ModuleGrouping

  defp e(id, module, position), do: %{id: id, module: module, position: position}

  test "groups by first-appearance order, collapsing blanks into one :default group" do
    entries = [
      e("a", "", 1),
      e("b", "M1", 2),
      e("c", "M1", 3),
      e("d", nil, 4),
      e("e", "M2", 5),
      e("f", "M1", 6)
    ]

    assert ModuleGrouping.group(entries) == [
             %{key: :default, entry_ids: ["a", "d"]},
             %{key: "M1", entry_ids: ["b", "c", "f"]},
             %{key: "M2", entry_ids: ["e"]}
           ]
  end
end
