defmodule TeacherAssistant.Academics.AssignmentsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    %{head: head, scope: scope, school: school, year: year, cg: cg}
  end

  test "assign creates a school context derived from the class", ctx do
    %{head: head, scope: scope, cg: cg} = ctx
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", weekly_hours: 5})
    assert tc.teacher_user_id == head.id
    assert tc.class_group_id == cg.id
    assert tc.level == "6ème"
    assert tc.weekly_hours == 5
  end

  test "assign rejects a non-member", %{cg: cg, scope: scope} do
    outsider = TeacherFixtures.user_fixture()

    assert {:error, :not_assignable} =
             Curriculum.assign_teacher(scope, cg, outsider, %{subject: "Maths"})
  end

  test "one teacher per subject per class; reassign swaps", ctx do
    %{head: head, school: school, scope: scope, cg: cg} = ctx
    other = TeacherFixtures.user_fixture()
    {:ok, _m} = add_active_member(school, head, other)

    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    assert {:error, :already_assigned} =
             Curriculum.assign_teacher(scope, cg, other, %{subject: "Maths"})

    {:ok, tc} = Curriculum.reassign_teacher(scope, tc, other)
    assert tc.teacher_user_id == other.id
  end

  test "remove is blocked when the context has data", ctx do
    %{head: head, scope: scope, cg: cg} = ctx
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _plan} = Curriculum.create_progression_plan(scope, tc, %{title: "Plan"})
    assert {:error, :has_data} = Curriculum.remove_assignment(scope, tc)
  end

  test "remove deletes a data-free assignment", ctx do
    %{head: head, scope: scope, cg: cg} = ctx
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    assert :ok = Curriculum.remove_assignment(scope, tc)
    assert Curriculum.list_assignments_for_class(scope, cg) == []
  end

  test "list_for_user returns only this user's assignments", ctx do
    %{head: head, school: school, year: year, scope: scope, cg: cg} = ctx
    other = TeacherFixtures.user_fixture()
    {:ok, _} = add_active_member(school, head, other)
    {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg, other, %{subject: "Anglais"})

    assert [%{subject: "Maths"}] = Curriculum.list_assignments_for_user(scope, year, head)
  end

  describe "coefficient (P2.3)" do
    test "assign accepts a coefficient; defaults to 1", ctx do
      %{head: head, scope: scope, cg: cg} = ctx

      {:ok, tc} =
        Curriculum.assign_teacher(scope, cg, head, %{
          subject: "Maths",
          coefficient: Decimal.new(4)
        })

      assert Decimal.equal?(tc.coefficient, Decimal.new(4))

      other = TeacherFixtures.user_fixture()
      {:ok, _} = add_active_member(ctx.school, head, other)
      {:ok, tc2} = Curriculum.assign_teacher(scope, cg, other, %{subject: "Anglais"})
      assert Decimal.equal?(tc2.coefficient, Decimal.new(1))
    end

    test "set_coefficient updates a valid positive value", ctx do
      %{head: head, scope: scope, cg: cg} = ctx
      {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
      {:ok, tc} = Curriculum.set_assignment_coefficient(scope, tc, "3")
      assert Decimal.equal?(tc.coefficient, Decimal.new(3))
    end

    test "set_coefficient rejects zero, negative and non-numeric", ctx do
      %{head: head, scope: scope, cg: cg} = ctx
      {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      assert {:error, :invalid_coefficient} =
               Curriculum.set_assignment_coefficient(scope, tc, "0")

      assert {:error, :invalid_coefficient} =
               Curriculum.set_assignment_coefficient(scope, tc, "-2")

      assert {:error, :invalid_coefficient} =
               Curriculum.set_assignment_coefficient(scope, tc, "abc")
    end
  end

  describe "combinable_siblings (P2 combined courses)" do
    setup ctx do
      %{year: year, scope: scope} = ctx

      {:ok, cg2} =
        Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

      %{cg2: cg2}
    end

    test "finds another class with the same teacher and subject", ctx do
      %{head: head, scope: scope, cg: cg, cg2: cg2} = ctx
      {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
      {:ok, tc2} = Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})

      assert [%{id: id}] = Curriculum.combinable_siblings(scope, tc)
      assert id == tc2.id
    end

    test "excludes a different subject or a different teacher", ctx do
      %{head: head, school: school, scope: scope, cg: cg, cg2: cg2} = ctx
      other = TeacherFixtures.user_fixture()
      {:ok, _} = add_active_member(school, head, other)

      {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
      {:ok, _} = Curriculum.assign_teacher(scope, cg2, head, %{subject: "Anglais"})
      {:ok, _} = Curriculum.assign_teacher(scope, cg2, other, %{subject: "Maths"})

      assert Curriculum.combinable_siblings(scope, tc) == []
    end

    test "excludes a sibling already part of a combined course", ctx do
      %{head: head, scope: scope, cg: cg, cg2: cg2} = ctx
      {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
      {:ok, tc2} = Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})
      {:ok, _course} = TeacherAssistant.Curriculum.combine_course(scope, [tc, tc2])

      {:ok, cg3} =
        Enrollment.create_class_group(scope, ctx.year, %{label: "6e C", level: "6ème"})

      {:ok, tc3} = Curriculum.assign_teacher(scope, cg3, head, %{subject: "Maths"})

      assert Curriculum.combinable_siblings(scope, tc3) == []
    end
  end

  # Creates an active membership for `user` in `school` via the invitation flow.
  defp add_active_member(school, head, user) do
    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(user.email),
        roles: [:teacher]
      })

    Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: user}, inv.token)
  end
end
