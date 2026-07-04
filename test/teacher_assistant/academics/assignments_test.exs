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

  # Creates an active membership for `user` in `school` via the invitation flow.
  defp add_active_member(school, head, user) do
    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    Schools.accept_invitation(inv.token, user)
  end
end
