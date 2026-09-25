defmodule TeacherAssistant.TenancyIsolationTest do
  @moduledoc """
  For every multitenant resource: a row created under school A is invisible
  under school B, and a create without a tenant raises. Later tasks add
  `row_for/2` clauses as they flip domains.
  """
  use TeacherAssistant.DataCase, async: true
  require Ash.Query
  alias TeacherAssistant.Academics, as: A
  alias TeacherAssistant.Accounts.{SchoolInvitation, SchoolMembership}
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: a, year: year_a} = TeacherFixtures.setup_complete_school_fixture()
    %{workspace: b} = TeacherFixtures.setup_complete_school_fixture()
    %{a: a, b: b, year_a: year_a}
  end

  # The school's head's scope — for fixtures that now need a `%Scope{}`.
  defp scope_of(school) do
    {:ok, profile} =
      TeacherAssistant.Accounts.fetch_school_profile(%TeacherAssistant.Scope{
        current_workspace: school
      })

    head = TeacherAssistant.Accounts.session_user(profile.owner_user_id)
    school_scope(head, school)
  end

  # One clause per resource; returns a row created under `school`.
  defp row_for(A.AcademicYear, school, _ctx),
    do: Organization.current_academic_year(scope_of(school))

  defp row_for(A.Term, school, _ctx) do
    scope = scope_of(school)
    year = Organization.current_academic_year(scope)
    Organization.list_terms(scope, year) |> List.first()
  end

  defp row_for(A.Sequence, school, _ctx) do
    scope = scope_of(school)
    year = Organization.current_academic_year(scope)
    Organization.list_sequences(scope, year) |> List.first()
  end

  defp row_for(A.ClassGroup, school, _ctx) do
    scope = scope_of(school)
    year = Organization.current_academic_year(scope)
    TeacherAssistant.Enrollment.list_class_groups(scope, year) |> List.first()
  end

  defp row_for(A.Student, school, ctx), do: row_for(A.Enrollment, school, ctx).student

  defp row_for(A.Enrollment, school, ctx) do
    cg = row_for(A.ClassGroup, school, ctx)

    {:ok, _} =
      TeacherAssistant.Enrollment.add_student(scope_of(school), cg, %{
        full_name: "Iso #{System.unique_integer([:positive])}",
        sex: :m
      })

    cg
    |> then(&TeacherAssistant.Enrollment.list_roster(scope_of(school), &1))
    |> List.first()
    |> Map.fetch!(:enrollment)
  end

  defp row_for(A.Subject, school, _ctx),
    do: school |> scope_of() |> TeacherAssistant.Curriculum.list_subjects() |> List.first()

  defp row_for(A.TeachingContext, school, _ctx) do
    scope = scope_of(school)
    TeacherFixtures.assigned_context_fixture(scope, Organization.current_academic_year(scope))
  end

  defp row_for(A.CombinedCourse, school, _ctx) do
    scope = scope_of(school)
    year = Organization.current_academic_year(scope)
    teacher = scope.current_user

    tc1 =
      TeacherFixtures.assigned_context_fixture(scope, year, %{teacher: teacher, subject: "Maths"})

    tc2 =
      TeacherFixtures.assigned_context_fixture(scope, year, %{teacher: teacher, subject: "Maths"})

    {:ok, course} = TeacherAssistant.Curriculum.combine_course(scope, [tc1, tc2])
    course
  end

  defp row_for(A.ProgressionPlan, school, ctx) do
    course = row_for(A.CombinedCourse, school, ctx)

    TeacherAssistant.Curriculum.list_progression_plans!(scope: scope_of(school))
    |> Enum.find(&(&1.combined_course_id == course.id))
  end

  defp row_for(A.ProgressionModule, school, ctx) do
    plan = row_for(A.ProgressionPlan, school, ctx)
    {:ok, m} = TeacherAssistant.Curriculum.create_module(scope_of(school), plan, %{title: "Iso"})
    m
  end

  defp row_for(A.ProgressionEntry, school, ctx) do
    m = row_for(A.ProgressionModule, school, ctx)

    {:ok, e} =
      TeacherAssistant.Curriculum.add_progression_entry(scope_of(school), m, %{
        lesson_title: "Iso",
        planned_hours: Decimal.new(1),
        entry_type: :lesson
      })

    e
  end

  defp row_for(A.LessonPlan, school, ctx) do
    entry = row_for(A.ProgressionEntry, school, ctx)
    tc = row_for(A.TeachingContext, school, ctx)
    {:ok, lp} = TeacherAssistant.Curriculum.ensure_lesson_plan(scope_of(school), entry, tc)
    lp
  end

  defp row_for(A.LessonStep, school, ctx) do
    lp = row_for(A.LessonPlan, school, ctx)

    {:ok, step} =
      TeacherAssistant.Curriculum.add_lesson_step(scope_of(school), lp, %{etape: "Iso"})

    step
  end

  defp row_for(A.Assessment, school, ctx) do
    scope = scope_of(school)
    tc = row_for(A.TeachingContext, school, ctx)

    year = Organization.current_academic_year(scope)
    seq = Organization.list_sequences(scope, year) |> List.first()

    {:ok, a} =
      TeacherAssistant.Assessment.create_assessment(scope, tc, seq, %{label: "Iso"})

    a
  end

  defp row_for(A.Mark, school, ctx) do
    a = row_for(A.Assessment, school, ctx)

    {:ok, tc} =
      TeacherAssistant.Curriculum.get_teaching_context(scope_of(school), a.teaching_context_id)

    {:ok, cg} =
      TeacherAssistant.Enrollment.fetch_owned_class_group(scope_of(school), tc.class_group_id)

    {:ok, _} =
      TeacherAssistant.Enrollment.add_student(scope_of(school), cg, %{
        full_name: "Marked",
        sex: :f
      })

    [%{student: s} | _] = TeacherAssistant.Enrollment.list_roster(scope_of(school), cg)

    :ok =
      TeacherAssistant.Assessment.upsert_marks(scope_of(school), a, [
        %{student_id: s.id, score: Decimal.new("12")}
      ])

    a |> then(&TeacherAssistant.Assessment.list_marks(scope_of(school), &1)) |> List.first()
  end

  defp row_for(A.Period, school, _ctx),
    do: school |> scope_of() |> TeacherAssistant.Attendance.list_periods() |> List.first()

  defp row_for(SchoolMembership, school, _ctx),
    do: TeacherAssistant.Accounts.list_members(scope_of(school)) |> List.first()

  defp row_for(SchoolInvitation, school, _ctx) do
    scope = scope_of(school)

    {:ok, inv} =
      TeacherAssistant.Accounts.invite_member(scope, %{
        email: "iso-#{System.unique_integer([:positive])}@example.com",
        roles: [:teacher]
      })

    inv
  end

  defp row_for(A.AttendanceEntry, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)

    {:ok, cg} =
      TeacherAssistant.Enrollment.fetch_owned_class_group(scope_of(school), e.class_group_id)

    p = row_for(A.Period, school, ctx)

    {:ok, _} =
      TeacherAssistant.Attendance.record_period(
        scope_of(school),
        cg,
        p,
        nil,
        ~D[2030-10-07],
        [{e.id, :absent}]
      )

    A.AttendanceEntry
    |> Ash.Query.filter(enrollment_id == ^e.id)
    |> Ash.read!(tenant: school.id)
    |> List.first()
  end

  defp row_for(A.TimetableSlot, school, ctx) do
    tc = row_for(A.TeachingContext, school, ctx)

    {:ok, cg} =
      TeacherAssistant.Enrollment.fetch_owned_class_group(scope_of(school), tc.class_group_id)

    p = row_for(A.Period, school, ctx)

    {:ok, slot} =
      TeacherAssistant.Timetabling.place_slot(scope_of(school), cg, %{
        day: :monday,
        period_id: p.id,
        teaching_context_id: tc.id
      })

    slot
  end

  defp row_for(A.SanctionEntry, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)

    {:ok, s} =
      TeacherAssistant.Discipline.add_sanction(
        scope_of(school),
        e,
        %{type: :avertissement, date: ~D[2030-10-07], reason: "Iso"}
      )

    s
  end

  defp row_for(A.ConductMark, school, ctx) do
    scope = scope_of(school)
    e = row_for(A.Enrollment, school, ctx)

    year = Organization.current_academic_year(scope)
    seq = Organization.list_sequences(scope, year) |> List.first()

    {:ok, m} = TeacherAssistant.Discipline.set_conduct_mark(scope, e, seq, 15)
    m
  end

  defp row_for(A.FeeTranche, school, ctx) do
    cg = row_for(A.ClassGroup, school, ctx)

    {:ok, t} =
      TeacherAssistant.Fees.add_tranche(scope_of(school), cg, %{
        label: "T1",
        amount: 10_000,
        due_date: ~D[2030-10-01]
      })

    t
  end

  defp row_for(A.Payment, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)

    {:ok, p} =
      TeacherAssistant.Fees.record_payment(
        scope_of(school),
        e,
        %{amount: 5_000, method: :cash, paid_on: ~D[2030-10-02]}
      )

    p
  end

  defp row_for(A.FeeAdjustment, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)

    {:ok, adj} =
      TeacherAssistant.Fees.set_adjustment(scope_of(school), e, %{amount: 1_000, reason: "Iso"})

    adj
  end

  defp row_for(A.TeachingLogEntry, school, ctx) do
    entry = row_for(A.ProgressionEntry, school, ctx)

    {:ok, log} =
      TeacherAssistant.Curriculum.log_teaching(scope_of(school), %{
        progression_entry_id: entry.id,
        date: Date.utc_today(),
        content_taught: "Iso",
        hours: Decimal.new(1)
      })

    log
  end

  @flipped [
    A.AcademicYear,
    A.Term,
    A.Sequence,
    A.ClassGroup,
    A.Student,
    A.Enrollment,
    A.Subject,
    A.TeachingContext,
    A.CombinedCourse,
    A.ProgressionPlan,
    A.ProgressionModule,
    A.ProgressionEntry,
    A.LessonPlan,
    A.LessonStep,
    A.TeachingLogEntry,
    A.Assessment,
    A.Mark,
    A.Period,
    A.AttendanceEntry,
    A.TimetableSlot,
    A.SanctionEntry,
    A.ConductMark,
    A.FeeTranche,
    A.Payment,
    A.FeeAdjustment
  ]

  # Global multitenant resources (`global? true`): readable under any tenant
  # they belong to, invisible under a different tenant, and still readable
  # with no tenant at all (the whole point of `global?`).
  @global [SchoolMembership, SchoolInvitation]

  test "a global resource is invisible under a different tenant but readable without one", ctx do
    for resource <- @global do
      row = row_for(resource, ctx.a, ctx)
      assert row, "#{inspect(resource)}: no row created"
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(resource, row.id, tenant: ctx.b.id)
      assert {:ok, _} = Ash.get(resource, row.id)
    end
  end

  test "a row of school A is not readable under school B", ctx do
    for resource <- @flipped do
      row = row_for(resource, ctx.a, ctx)
      assert row, "#{inspect(resource)}: no row created"
      assert {:ok, _} = Ash.get(resource, row.id, tenant: ctx.a.id)
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(resource, row.id, tenant: ctx.b.id)
    end
  end

  test "reading a flipped resource without a tenant raises", ctx do
    for resource <- @flipped do
      assert_raise Ash.Error.Invalid, fn ->
        resource |> Ash.Query.filter(id == ^row_for(resource, ctx.a, ctx).id) |> Ash.read!()
      end
    end
  end

  test "creating a flipped resource without a tenant raises", %{a: a} do
    year = Organization.current_academic_year(scope_of(a))

    assert_raise Ash.Error.Invalid, ~r/tenant/, fn ->
      A.Term
      |> Ash.Changeset.for_create(:create, %{position: 9, academic_year_id: year.id})
      |> Ash.create!()
    end
  end

  test "the scope exposes the workspace as tenant", %{a: a} do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope_of(a))
    head = TeacherAssistant.Accounts.session_user(profile.owner_user_id)
    {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(head, a.id)
    assert Ash.Scope.ToOpts.get_tenant(scope) == {:ok, a.id}
  end

  test "a class group of school A cannot be fetched as owned by school B", %{a: a, b: b} = ctx do
    cg = row_for(A.ClassGroup, a, ctx)
    assert {:ok, _} = TeacherAssistant.Enrollment.fetch_owned_class_group(scope_of(a), cg.id)

    assert {:error, :not_found} =
             TeacherAssistant.Enrollment.fetch_owned_class_group(scope_of(b), cg.id)
  end

  test "justifying an absence of school A's student from school B's scope is not found, " <>
         "and recording attendance against school B's period is rejected (F1)",
       %{
         a: a,
         b: b
       } = ctx do
    entry = row_for(A.AttendanceEntry, a, ctx)

    {:ok, e} =
      TeacherAssistant.Enrollment.fetch_owned_enrollment(scope_of(a), entry.enrollment_id)

    assert {:ok, _} = TeacherAssistant.Attendance.justify_day(scope_of(a), e, entry.date, "ok")

    assert {:error, :not_found} =
             TeacherAssistant.Enrollment.fetch_owned_enrollment(scope_of(b), entry.enrollment_id)

    # M7 / F1: the database rejects a cross-workspace combination
    # (a's class group paired with b's period) — nothing is written.
    cg_a = row_for(A.ClassGroup, a, ctx)
    period_b = row_for(A.Period, b, ctx)

    before =
      A.AttendanceEntry |> Ash.Query.for_read(:read) |> Ash.Query.set_tenant(a.id) |> Ash.read!()

    assert {:error, _} =
             TeacherAssistant.Attendance.record_period(
               scope_of(a),
               cg_a,
               period_b,
               nil,
               entry.date,
               [{e.id, :present}]
             )

    assert A.AttendanceEntry
           |> Ash.Query.for_read(:read)
           |> Ash.Query.set_tenant(a.id)
           |> Ash.read!() == before
  end

  test "a payment can be recorded for school A's own enrollment (school B cannot see it), " <>
         "and recording a conduct mark against school B's sequence is rejected (F1)",
       %{a: a, b: b} = ctx do
    e = row_for(A.Enrollment, a, ctx)

    assert {:error, :not_found} =
             TeacherAssistant.Enrollment.fetch_owned_enrollment(scope_of(b), e.id)

    assert {:ok, _} =
             TeacherAssistant.Fees.record_payment(
               scope_of(a),
               e,
               %{amount: 1_000, method: :cash, paid_on: ~D[2030-10-03]}
             )

    assert TeacherAssistant.Fees.list_payments(scope_of(a), e)
           |> Enum.all?(&(&1.workspace_id == a.id))

    # M7 / F1: the database rejects a cross-workspace combination
    # (a's enrollment paired with b's sequence) — nothing is written.
    seq_b =
      Organization.list_sequences(scope_of(b), Organization.current_academic_year(scope_of(b)))
      |> List.first()

    assert {:error, _} = TeacherAssistant.Discipline.set_conduct_mark(scope_of(a), e, seq_b, 15)

    assert A.ConductMark
           |> Ash.Query.for_read(:read)
           |> Ash.Query.set_tenant(a.id)
           |> Ash.read!() == []
  end

  test "SchoolMembership :active_for_workspace requires a tenant while :active_for_user does not (F3)",
       %{a: a} do
    assert_raise Ash.Error.Invalid, fn ->
      SchoolMembership |> Ash.Query.for_read(:active_for_workspace) |> Ash.read!()
    end

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope_of(a))
    head = TeacherAssistant.Accounts.session_user(profile.owner_user_id)

    assert {:ok, _memberships} =
             SchoolMembership
             |> Ash.Query.for_read(:active_for_user, %{user_id: head.id})
             |> Ash.read()
  end
end
