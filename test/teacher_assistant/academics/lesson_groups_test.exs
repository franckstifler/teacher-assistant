defmodule TeacherAssistant.Academics.LessonGroupsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.LessonGroups

  @p4 %{id: "p4", position: 4, start_time: ~T[10:15:00], end_time: ~T[11:05:00]}
  @p5 %{id: "p5", position: 5, start_time: ~T[11:05:00], end_time: ~T[11:55:00]}
  @p7 %{id: "p7", position: 7, start_time: ~T[13:30:00], end_time: ~T[14:20:00]}

  defp lesson(period, class, opts \\ []) do
    %{
      period: period,
      class_group: %{id: class, label: class},
      teaching_context_id: "tc-" <> class <> Keyword.get(opts, :subject, ""),
      combined_course_id: opts[:course],
      status: Keyword.get(opts, :status, :upcoming),
      absent: Keyword.get(opts, :absent, 0)
    }
  end

  test "a combined course placed in each class is one lesson per period" do
    groups =
      LessonGroups.group([
        lesson(@p4, "ESF 2", course: "c1", status: :done, absent: 1),
        lesson(@p4, "COME 2", course: "c1", status: :in_progress),
        lesson(@p7, "MENU 4")
      ])

    assert [combined, solo] = groups
    assert combined.unit == {:course, "c1"}
    assert Enum.map(combined.members, & &1.class_group.label) == ["COME 2", "ESF 2"]
    # the roll call opens through the first member class
    assert combined.key == "COME 2-p4"
    # one class still to call keeps the lesson to do; absences add up
    assert combined.status == :in_progress
    assert combined.absent == 1
    assert LessonGroups.combined?(combined)
    refute LessonGroups.combined?(solo)
    assert LessonGroups.class_ids(combined) == ["COME 2", "ESF 2"]
  end

  test "back-to-back lessons of the same course count hours; a gap starts again" do
    groups =
      LessonGroups.group([
        lesson(@p5, "COME 2", course: "c1"),
        lesson(@p4, "COME 2", course: "c1"),
        lesson(@p5, "ESF 2", course: "c1"),
        lesson(@p7, "COME 2", course: "c1")
      ])

    assert Enum.map(groups, &{&1.period.id, &1.hour}) == [{"p4", 1}, {"p5", 2}, {"p7", 1}]
  end

  test "two solo courses in the same period stay apart (a clash)" do
    groups = LessonGroups.group([lesson(@p4, "6e A"), lesson(@p4, "6e B")])
    assert length(groups) == 2
    assert Enum.all?(groups, &(&1.hour == 1))
  end

  test "a moved cell groups on its own and keeps the flag; covered sits after not held" do
    [moved] = LessonGroups.group([lesson(@p4, "6e A", status: :done) |> Map.put(:moved?, true)])
    assert moved.moved? == true
    assert moved.status == :done

    [plain] = LessonGroups.group([lesson(@p4, "6e A", status: :done)])
    assert plain.moved? == false

    [g] =
      LessonGroups.group([
        lesson(@p4, "A", course: "c", status: :covered),
        lesson(@p4, "B", course: "c", status: :upcoming)
      ])

    assert g.status == :covered

    [g] =
      LessonGroups.group([
        lesson(@p4, "A", course: "c", status: :covered),
        lesson(@p4, "B", course: "c", status: :not_held)
      ])

    assert g.status == :not_held
  end

  test "slot views without status keep no status" do
    [group] =
      LessonGroups.group([
        %{period: @p4, class_group_id: "cg", class_label: "6e A", combined_course_id: nil}
      ])

    refute Map.has_key?(group, :status)
    assert group.key == "cg-p4"
  end
end
