defmodule TeacherAssistant.ScopePlumbingTest do
  @moduledoc "The scope's user is who a write is attributed to (spec §4.5, plan C1)."
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Discipline, Enrollment, Fees, Organization}

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    [cg | _] = Enrollment.list_class_groups(ws, year)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(cg, %{full_name: "Awa Ndi", sex: :f})
    [seq | _] = Organization.list_sequences(year)
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
end
