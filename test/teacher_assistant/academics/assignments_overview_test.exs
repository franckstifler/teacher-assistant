defmodule TeacherAssistant.Academics.AssignmentsOverviewTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Curriculum, Enrollment}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

    :ok =
      Curriculum.update_coefficient_grid(scope, %{
        "cells" => %{maths.id => %{Curriculum.cell_token({:francophone, "6ème", nil}) => "4"}},
        "groups" => %{}
      })

    other = TeacherFixtures.membership_fixture(scope)
    %{scope: scope, head: head, cg: cg, maths: maths, other: other}
  end

  test "an unassigned grid subject is to assign; placing assigns, then reassigns with the hours",
       ctx do
    %{scope: scope, cg: cg, maths: maths, head: head, other: other} = ctx
    g = Curriculum.assignment_overview(scope)
    assert %{kind: :to_assign} = g.cells[{cg.id, maths.id}]

    assert {:ok, tc} = Curriculum.place_assignment(scope, cg, maths, head.id, "5")
    assert tc.weekly_hours == 5

    assert %{kind: :assigned, teacher_id: tid} =
             Curriculum.assignment_overview(scope).cells[{cg.id, maths.id}]

    assert tid == head.id
    assert Curriculum.assignment_overview(scope).loads[head.id].load >= 5

    assert {:ok, tc2} = Curriculum.place_assignment(scope, cg, maths, other.user_id, "3")
    assert tc2.id == tc.id
    assert tc2.teacher_user_id == other.user_id
    assert tc2.weekly_hours == 3
  end

  test "refuses a non-member, bad hours, or another school's class", ctx do
    %{scope: scope, cg: cg, maths: maths} = ctx
    stranger = TeacherFixtures.user_fixture()

    assert {:error, :not_assignable} =
             Curriculum.place_assignment(scope, cg, maths, stranger.id, "4")

    assert {:error, :invalid_hours} =
             Curriculum.place_assignment(scope, cg, maths, ctx.head.id, "0")

    %{scope: other_scope} = TeacherFixtures.setup_complete_school_fixture()
    # even for a teacher who belongs to both schools, another school's class is refused
    TeacherFixtures.membership_fixture(other_scope, %{user: ctx.head})

    assert {:error, :not_found} =
             Curriculum.place_assignment(other_scope, cg, maths, ctx.head.id, "4")

    assert Curriculum.assignment_at(scope, cg, maths.id) == nil
  end

  test "a plain teacher cannot place", ctx do
    teacher = %{
      TeacherFixtures.member_scope_fixture(ctx.scope)
      | current_academic_year: ctx.scope.current_academic_year
    }

    assert {:error, %Ash.Error.Forbidden{}} =
             Curriculum.place_assignment(teacher, ctx.cg, ctx.maths, ctx.head.id, "4")
  end

  test "hours up to 40 are accepted, as on the class page", ctx do
    assert {:ok, tc} =
             Curriculum.place_assignment(ctx.scope, ctx.cg, ctx.maths, ctx.head.id, "24")

    assert tc.weekly_hours == 24

    assert {:error, :invalid_hours} =
             Curriculum.place_assignment(ctx.scope, ctx.cg, ctx.maths, ctx.head.id, "41")
  end

  describe "unassigned_subjects_by_class/2" do
    test "lists the grid's subjects with no teacher in the class, by name", ctx do
      %{scope: scope, cg: cg, maths: maths, head: head} = ctx
      year = scope.current_academic_year
      classes = Enrollment.list_class_groups(scope, year)

      before = Curriculum.unassigned_subjects_by_class(scope, classes)[cg.id]
      assert maths.id in Enum.map(before, & &1.id)
      names = Enum.map(before, &String.downcase(&1.name))
      assert names == Enum.sort(names)

      {:ok, _} = Curriculum.place_assignment(scope, cg, maths, head.id, "4")
      after_ = Curriculum.unassigned_subjects_by_class(scope, classes)[cg.id]
      assert length(after_) == length(before) - 1
      refute maths.id in Enum.map(after_, & &1.id)
    end

    test "a level with no grid row flags nothing", ctx do
      %{scope: scope} = ctx
      year = scope.current_academic_year

      {:ok, cg} =
        Enrollment.create_class_group(scope, year, %{label: "Pass", level: "Passerelle"})

      assert Curriculum.unassigned_subjects_by_class(scope, [cg]) == %{cg.id => []}
    end
  end
end
