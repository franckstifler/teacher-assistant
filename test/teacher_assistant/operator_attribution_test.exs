defmodule TeacherAssistant.OperatorAttributionTest do
  @moduledoc "Writes made while an operator acts as a member carry the operator (A6)."
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.{Accounts, Assessment, Attendance, Discipline, Enrollment, Fees}
  alias TeacherAssistant.{FeesFixtures, MarksFixtures, Organization, TeacherFixtures, Timetabling}
  alias TeacherAssistant.Academics.{AttendanceEntry, MarkEvent}
  alias TeacherAssistant.Accounts.AuditEvent

  setup do
    world = MarksFixtures.marks_world()
    op = TeacherFixtures.admin_user_fixture()
    Map.merge(world, %{op: op, ws_id: world.head.current_workspace.id})
  end

  defp events(ctx) do
    MarkEvent
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read!(tenant: ctx.ws_id, authorize?: false)
  end

  test "a mark written while impersonated journals the operator; the member's own does not",
       ctx do
    :ok =
      Assessment.upsert_marks(impersonating(ctx.t, ctx.op), ctx.a, [
        %{student_id: ctx.s1.id, score: Decimal.new(12)}
      ])

    :ok = Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s2.id, score: Decimal.new(9)}])

    assert [%{operator_user_id: op_id, actor_user_id: actor}, %{operator_user_id: nil}] =
             events(ctx)

    assert op_id == ctx.op.id
    assert actor == ctx.t.current_user.id
  end

  test "a correction requested and approved while impersonated journals the operator", ctx do
    :ok =
      Assessment.upsert_marks(ctx.t, ctx.a, [%{student_id: ctx.s1.id, score: Decimal.new(12)}])

    MarksFixtures.lock!(ctx, Date.add(TeacherAssistant.Academics.Reference.today(), -1))
    censeur = TeacherFixtures.member_scope_fixture(ctx.head, %{roles: [:vice_principal]})

    {:ok, c} =
      Assessment.request_correction(impersonating(ctx.t, ctx.op), %{
        assessment_id: ctx.a.id,
        student_id: ctx.s1.id,
        requested_status: :graded,
        requested_score: Decimal.new(14),
        motive: :erreur_saisie
      })

    {:ok, _} = Assessment.approve_correction(impersonating(censeur, ctx.op), c)

    by_action = Map.new(events(ctx), &{&1.action, &1.operator_user_id})
    assert by_action[:saisie] == nil
    assert by_action[:correction_demandee] == ctx.op.id
    assert by_action[:correction_approuvee] == ctx.op.id
  end

  test "a payment and its cancellation carry their operator columns" do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    op = TeacherFixtures.admin_user_fixture()
    %{e: e} = FeesFixtures.fees_setup(head, year)
    imp = impersonating(head, op)

    {:ok, payment} = Fees.record_payment(imp, e, FeesFixtures.cash(10_000))
    assert payment.operator_user_id == op.id
    assert payment.recorded_by_user_id == head.current_user.id

    {:ok, cancelled} = Fees.cancel_payment(imp, payment, "erreur de saisie")
    assert cancelled.cancelled_operator_user_id == op.id

    {:ok, own} = Fees.record_payment(head, e, FeesFixtures.cash(5_000))
    assert own.operator_user_id == nil
  end

  test "a sanction and its parents-notified stamp carry the operator" do
    %{year: year, scope: head} = TeacherFixtures.setup_complete_school_fixture()
    op = TeacherFixtures.admin_user_fixture()
    [cg | _] = Enrollment.list_class_groups(head, year)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(head, cg, %{full_name: "Awa Ndi", sex: :f})
    [seq | _] = Organization.list_sequences(head, year)
    imp = impersonating(head, op)

    {:ok, s} = Discipline.add_sanction(imp, e, %{type: :avertissement, date: seq.start_date})
    assert s.operator_user_id == op.id

    {:ok, s} = Discipline.mark_parents_notified(imp, s)
    assert s.parents_notified_operator_user_id == op.id
  end

  test "a roll call taken while impersonated carries the operator; retaken by the member it is cleared" do
    %{scope: head, year: year, head_user: head_user} =
      TeacherFixtures.setup_complete_school_fixture()

    :ok = TeacherFixtures.verify_school!(head)
    op = TeacherFixtures.admin_user_fixture()
    [cg | _] = Enrollment.list_class_groups(head, year)

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(head, cg, head_user, %{subject: "Maths"})

    {:ok, _} = Enrollment.add_student(head, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(head, cg)
    :ok = Attendance.build_default_periods(head)
    period = head |> Attendance.list_periods() |> Enum.find(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(head, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    date = ~D[2025-09-15]

    {:ok, 1} =
      Attendance.record_period(impersonating(head, op), cg, period, tc, date, [{e.id, :absent}])

    assert [%{operator_user_id: op_id}] = Ash.read!(AttendanceEntry, scope: head)
    assert op_id == op.id

    {:ok, 1} = Attendance.record_period(head, cg, period, tc, date, [{e.id, :present}])
    assert [%{operator_user_id: nil, status: :present}] = Ash.read!(AttendanceEntry, scope: head)
  end

  test "a member renamed during impersonation journals the operator" do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    op = TeacherFixtures.admin_user_fixture()
    m = TeacherFixtures.membership_fixture(head, %{roles: [:teacher]})
    {:ok, m} = Ash.load(m, :user, scope: head)

    {:ok, _} = Accounts.rename_member(impersonating(head, op), m, "Hélène Mvondo")

    assert [%{operator_user_id: op_id, action: :member_renamed}] =
             AuditEvent
             |> Ash.Query.filter(target_user_id == ^m.user_id)
             |> Ash.read!(authorize?: false)

    assert op_id == op.id
  end
end
