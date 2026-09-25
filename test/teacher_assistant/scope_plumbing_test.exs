defmodule TeacherAssistant.ScopePlumbingTest do
  @moduledoc "The scope's user is who a write is attributed to (spec §4.5, plan C1)."
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Fees, Organization}

  setup do
    %{workspace: _ws, year: year, scope: head} = setup_complete_school_fixture()
    [cg | _] = Enrollment.list_class_groups(head, year)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(head, cg, %{full_name: "Awa Ndi", sex: :f})
    [seq | _] = Organization.list_sequences(head, year)
    %{head: head, e: e, seq: seq}
  end

  test "Discipline attributes a sanction to the scope's user", %{head: head, e: e, seq: seq} do
    {:ok, s} = Discipline.add_sanction(head, e, %{type: :avertissement, date: seq.start_date})
    assert s.issued_by_user_id == head.current_user.id
  end

  test "Fees attributes a payment to the scope's user", %{head: head, e: e} do
    {:ok, p} =
      Fees.record_payment(head, e, %{amount: 5_000, paid_on: ~D[2025-10-01], method: :cash})

    assert p.recorded_by_user_id == head.current_user.id
  end

  test "Attendance attributes recorded entries to the scope's user", %{head: head, e: e} do
    [period | _] = Attendance.list_periods(head)
    {:ok, cg} = Enrollment.fetch_owned_class_group(head, e.class_group_id)

    assert {:ok, 1} =
             Attendance.record_period(head, cg, period, nil, ~D[2025-09-15], [
               {e.id, :absent}
             ])

    [entry] =
      Attendance.for_period_date_class!(period.id, ~D[2025-09-15], cg.id, scope: head)

    assert entry.recorded_by_user_id == head.current_user.id
  end

  test "Enrollment and Curriculum take the scope first", %{head: head, e: e} do
    {:ok, cg} = Enrollment.fetch_owned_class_group(head, e.class_group_id)
    assert [%{enrollment: %{id: id}}] = Enrollment.list_roster(head, cg)
    assert id == e.id
    assert is_list(TeacherAssistant.Curriculum.list_subjects(head))
  end

  test "Accounts attributes an invitation to the scope's user", %{head: head} do
    {:ok, inv} =
      TeacherAssistant.Accounts.invite_member(head, %{email: "x@example.com", roles: [:teacher]})

    assert inv.invited_by_user_id == head.current_user.id
  end
end
