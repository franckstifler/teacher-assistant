defmodule TeacherAssistant.Academics.AssignmentsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    %{head: head, school: school, year: year, cg: cg}
  end

  test "assign creates a school context derived from the class", ctx do
    %{head: head, cg: cg} = ctx
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", weekly_hours: 5})
    assert tc.teacher_user_id == head.id
    assert tc.class_group_id == cg.id
    assert tc.level == "6ème"
    assert tc.weekly_hours == 5
  end

  test "assign rejects a non-member", %{cg: cg} do
    outsider = TeacherFixtures.user_fixture()
    assert {:error, :not_assignable} = Assignments.assign(cg, outsider, %{subject: "Maths"})
  end

  test "one teacher per subject per class; reassign swaps", ctx do
    %{head: head, school: school, cg: cg} = ctx
    other = TeacherFixtures.user_fixture()
    {:ok, _m} = add_active_member(school, head, other)

    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    assert {:error, :already_assigned} = Assignments.assign(cg, other, %{subject: "Maths"})
    {:ok, tc} = Assignments.reassign(tc, other)
    assert tc.teacher_user_id == other.id
  end

  test "remove is blocked when the context has data", ctx do
    %{head: head, cg: cg} = ctx
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    {:ok, _plan} = Academics.create_progression_plan(tc, %{title: "Plan"})
    assert {:error, :has_data} = Assignments.remove(tc)
  end

  test "remove deletes a data-free assignment", ctx do
    %{head: head, cg: cg} = ctx
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    assert :ok = Assignments.remove(tc)
    assert Assignments.list_for_class(cg) == []
  end

  test "list_for_user returns only this user's assignments", ctx do
    %{head: head, school: school, year: year, cg: cg} = ctx
    other = TeacherFixtures.user_fixture()
    {:ok, _} = add_active_member(school, head, other)
    {:ok, _} = Assignments.assign(cg, head, %{subject: "Maths"})
    {:ok, _} = Assignments.assign(cg, other, %{subject: "Anglais"})

    assert [%{subject: "Maths"}] = Assignments.list_for_user(school, year, head)
  end

  describe "coefficient (P2.3)" do
    test "assign accepts a coefficient; defaults to 1", ctx do
      %{head: head, cg: cg} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})
      assert Decimal.equal?(tc.coefficient, Decimal.new(4))

      other = TeacherFixtures.user_fixture()
      {:ok, _} = add_active_member(ctx.school, head, other)
      {:ok, tc2} = Assignments.assign(cg, other, %{subject: "Anglais"})
      assert Decimal.equal?(tc2.coefficient, Decimal.new(1))
    end

    test "set_coefficient updates a valid positive value", ctx do
      %{head: head, cg: cg} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, tc} = Assignments.set_coefficient(tc, "3")
      assert Decimal.equal?(tc.coefficient, Decimal.new(3))
    end

    test "set_coefficient rejects zero, negative and non-numeric", ctx do
      %{head: head, cg: cg} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      assert {:error, :invalid_coefficient} = Assignments.set_coefficient(tc, "0")
      assert {:error, :invalid_coefficient} = Assignments.set_coefficient(tc, "-2")
      assert {:error, :invalid_coefficient} = Assignments.set_coefficient(tc, "abc")
    end
  end

  describe "combinable_siblings (P2 combined courses)" do
    setup ctx do
      %{school: school, year: year} = ctx
      {:ok, cg2} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})
      %{cg2: cg2}
    end

    test "finds another class with the same teacher and subject", ctx do
      %{head: head, cg: cg, cg2: cg2} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, tc2} = Assignments.assign(cg2, head, %{subject: "Maths"})

      assert [%{id: id}] = Assignments.combinable_siblings(tc)
      assert id == tc2.id
    end

    test "excludes a different subject or a different teacher", ctx do
      %{head: head, school: school, cg: cg, cg2: cg2} = ctx
      other = TeacherFixtures.user_fixture()
      {:ok, _} = add_active_member(school, head, other)

      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, _} = Assignments.assign(cg2, head, %{subject: "Anglais"})
      {:ok, _} = Assignments.assign(cg2, other, %{subject: "Maths"})

      assert Assignments.combinable_siblings(tc) == []
    end

    test "excludes a sibling already part of a combined course", ctx do
      %{head: head, cg: cg, cg2: cg2} = ctx
      {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, tc2} = Assignments.assign(cg2, head, %{subject: "Maths"})
      {:ok, _course} = TeacherAssistant.Academics.Courses.combine([tc, tc2])

      {:ok, cg3} =
        Academics.create_class_group(ctx.school, ctx.year, %{label: "6e C", level: "6ème"})

      {:ok, tc3} = Assignments.assign(cg3, head, %{subject: "Maths"})

      assert Assignments.combinable_siblings(tc3) == []
    end
  end

  # Creates an active membership for `user` in `school` via the invitation flow.
  defp add_active_member(school, head, user) do
    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    Schools.accept_invitation(inv.token, user)
  end
end
