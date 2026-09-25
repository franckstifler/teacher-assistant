defmodule TeacherAssistant.CrossWorkspaceGuardTest do
  @moduledoc """
  The database rejects cross-school writes: every domain function that receives
  more than one tenant-owned struct (or a raw id naming one) and writes must
  return an error tuple AND write nothing, because the composite foreign keys
  tie every tenant-to-tenant reference to the tenant. One test per guarded
  function, each built from two independent schools
  (`TeacherFixtures.setup_complete_school_fixture/1`), asserting the call
  returns `{:error, _}` and that nothing was written under either tenant.
  """
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Attendance, Curriculum, Discipline, Enrollment, Timetabling}
  alias TeacherAssistant.Academics.{AttendanceEntry, ConductMark, TimetableSlot}
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws_a, head_user: head_a, year: year_a, scope: scope_a} =
      TeacherFixtures.setup_complete_school_fixture()

    %{workspace: ws_b, head_user: head_b, year: year_b, scope: scope_b} =
      TeacherFixtures.setup_complete_school_fixture()

    {:ok, cg_a} = Enrollment.create_class_group(scope_a, year_a, %{label: "6e A", level: "6ème"})

    {:ok, cg_a2} =
      Enrollment.create_class_group(scope_a, year_a, %{label: "6e A2", level: "6ème"})

    {:ok, cg_b} = Enrollment.create_class_group(scope_b, year_b, %{label: "6e B", level: "6ème"})

    {:ok, %{student: student_a, enrollment: enrollment_a}} =
      Enrollment.enroll_new(scope_a, cg_a, %{full_name: "Awa A", sex: :f})

    {:ok, %{student: student_b}} =
      Enrollment.enroll_new(scope_b, cg_b, %{full_name: "Bia B", sex: :f})

    {:ok, tc_a} = Curriculum.assign_teacher(scope_a, cg_a, head_a, %{subject: "Maths"})
    {:ok, tc_a2} = Curriculum.assign_teacher(scope_a, cg_a2, head_a, %{subject: "Maths"})
    {:ok, tc_b} = Curriculum.assign_teacher(scope_b, cg_b, head_b, %{subject: "Maths"})

    {:ok, course_a} = Curriculum.combine_course(scope_a, [tc_a, tc_a2])

    seq_a = Organization.list_sequences(scope_a, year_a) |> List.first()
    seq_b = Organization.list_sequences(scope_b, year_b) |> List.first()

    period_a = Attendance.list_periods(scope_a) |> Enum.find(&(&1.kind == :lesson))
    period_b = Attendance.list_periods(scope_b) |> Enum.find(&(&1.kind == :lesson))

    {:ok, plan_a} = Curriculum.create_progression_plan(scope_a, tc_a, %{title: "Plan A"})
    {:ok, module_a} = Curriculum.create_module(scope_a, plan_a, %{title: "M1"})

    {:ok, plan_b} = Curriculum.create_progression_plan(scope_b, tc_b, %{title: "Plan B"})
    {:ok, module_b} = Curriculum.create_module(scope_b, plan_b, %{title: "M1"})

    {:ok, entry_b} =
      Curriculum.add_progression_entry(scope_b, module_b, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    %{
      ws_a: ws_a,
      ws_b: ws_b,
      head_a: head_a,
      head_b: head_b,
      scope_a: scope_a,
      scope_b: scope_b,
      year_a: year_a,
      year_b: year_b,
      cg_a: cg_a,
      cg_b: cg_b,
      student_a: student_a,
      student_b: student_b,
      enrollment_a: enrollment_a,
      tc_a: tc_a,
      tc_b: tc_b,
      course_a: course_a,
      seq_a: seq_a,
      seq_b: seq_b,
      period_a: period_a,
      period_b: period_b,
      module_a: module_a,
      entry_b: entry_b
    }
  end

  test "Assessment.create_assessment rejects a context/sequence workspace mismatch", ctx do
    assert {:error, _} =
             Assessment.create_assessment(ctx.scope_a, ctx.tc_a, ctx.seq_b, %{label: "D1"})

    assert count_all(TeacherAssistant.Academics.Assessment, ctx.ws_a.id) == 0
    assert count_all(TeacherAssistant.Academics.Assessment, ctx.ws_b.id) == 0
  end

  test "Assessment.create_combined_assessment rejects a course/sequence workspace mismatch",
       ctx do
    assert {:error, _} =
             Assessment.create_combined_assessment(ctx.scope_a, ctx.course_a, ctx.seq_b, %{
               label: "D1"
             })

    assert count_all(TeacherAssistant.Academics.Assessment, ctx.ws_a.id) == 0
    assert count_all(TeacherAssistant.Academics.Assessment, ctx.ws_b.id) == 0
  end

  test "Discipline.set_conduct_mark rejects an enrollment/sequence workspace mismatch", ctx do
    assert {:error, _} = Discipline.set_conduct_mark(ctx.scope_a, ctx.enrollment_a, ctx.seq_b, 15)

    assert count_all(ConductMark, ctx.ws_a.id) == 0
    assert count_all(ConductMark, ctx.ws_b.id) == 0
  end

  test "Discipline.note_de_conduite returns nil (never data) for a cross-workspace sequence",
       ctx do
    assert Discipline.note_de_conduite(ctx.scope_a, ctx.enrollment_a, {:sequence, ctx.seq_b}) ==
             nil
  end

  test "Enrollment.enroll_existing rejects a class_group/student workspace mismatch", ctx do
    assert {:error, _} = Enrollment.enroll_existing(ctx.scope_a, ctx.cg_a, ctx.student_b)

    assert Enrollment.list_roster(ctx.scope_a, ctx.cg_a) |> length() == 1
    assert Enrollment.list_roster(ctx.scope_b, ctx.cg_b) |> length() == 1
  end

  test "Enrollment.set_form_master requires an active membership in the class group's own workspace",
       ctx do
    assert {:error, :not_a_member} =
             Enrollment.set_form_master(ctx.scope_a, ctx.cg_a, ctx.head_b.id)

    {:ok, reloaded} = Enrollment.fetch_owned_class_group(ctx.scope_a, ctx.cg_a.id)
    assert reloaded.form_master_user_id == nil
  end

  test "Enrollment.create_class_group rejects a workspace/academic_year mismatch", ctx do
    assert {:error, _} =
             Enrollment.create_class_group(ctx.scope_a, ctx.year_b, %{
               label: "Bogus",
               level: "6ème"
             })

    refute Enrollment.list_class_groups(ctx.scope_a, ctx.year_a)
           |> Enum.any?(&(&1.label == "Bogus"))
  end

  test "Enrollment.transfer rejects an enrollment/class_group workspace mismatch", ctx do
    assert {:error, _} = Enrollment.transfer(ctx.scope_a, ctx.enrollment_a, ctx.cg_b)

    {:ok, reloaded} = Enrollment.fetch_owned_enrollment(ctx.scope_a, ctx.enrollment_a.id)
    assert reloaded.class_group_id == ctx.cg_a.id
  end

  test "Attendance.record_period rejects a class_group/period workspace mismatch", ctx do
    assert {:error, _} =
             Attendance.record_period(
               ctx.scope_a,
               ctx.cg_a,
               ctx.period_b,
               ctx.tc_a,
               ~D[2025-09-15],
               [{ctx.enrollment_a.id, :present}]
             )

    assert count_all(AttendanceEntry, ctx.ws_a.id) == 0
    assert count_all(AttendanceEntry, ctx.ws_b.id) == 0
  end

  test "Attendance.record_combined_period rejects a course/period workspace mismatch", ctx do
    assert {:error, _} =
             Attendance.record_combined_period(
               ctx.scope_a,
               ctx.course_a,
               ctx.period_b,
               ~D[2025-09-15],
               [{ctx.enrollment_a.id, :present}]
             )

    assert count_all(AttendanceEntry, ctx.ws_a.id) == 0
    assert count_all(AttendanceEntry, ctx.ws_b.id) == 0
  end

  test "Timetabling.place_slot rejects a foreign period_id", ctx do
    assert {:error, :invalid} =
             Timetabling.place_slot(ctx.scope_a, ctx.cg_a, %{
               day: :monday,
               period_id: ctx.period_b.id,
               teaching_context_id: ctx.tc_a.id
             })

    assert count_all(TimetableSlot, ctx.ws_a.id) == 0
    assert count_all(TimetableSlot, ctx.ws_b.id) == 0
  end

  test "Timetabling.place_combined_slot rejects a foreign period_id", ctx do
    assert {:error, :invalid} =
             Timetabling.place_combined_slot(ctx.scope_a, ctx.course_a, :monday, ctx.period_b.id)

    assert count_all(TimetableSlot, ctx.ws_a.id) == 0
    assert count_all(TimetableSlot, ctx.ws_b.id) == 0
  end

  test "Timetabling.clear_slot rejects a foreign period_id", ctx do
    {:ok, _slot} =
      Timetabling.place_slot(ctx.scope_a, ctx.cg_a, %{
        day: :monday,
        period_id: ctx.period_a.id,
        teaching_context_id: ctx.tc_a.id
      })

    assert {:error, :invalid} =
             Timetabling.clear_slot(ctx.scope_a, ctx.cg_a, :monday, ctx.period_b.id)

    assert count_all(TimetableSlot, ctx.ws_a.id) == 1
  end

  test "Timetabling.clear_combined_slot rejects a foreign period_id", ctx do
    assert {:error, :invalid} =
             Timetabling.clear_combined_slot(ctx.scope_a, ctx.course_a, :monday, ctx.period_b.id)
  end

  test "Curriculum.assign_module_sequence rejects a foreign sequence_id", ctx do
    assert {:error, :invalid} =
             Curriculum.assign_module_sequence(ctx.scope_a, ctx.module_a, ctx.seq_b.id)

    {:ok, reloaded} = Curriculum.fetch_owned_module(ctx.scope_a, ctx.module_a.id)
    assert reloaded.sequence_id == nil
  end

  test "Curriculum.log_teaching rejects a foreign progression_entry_id", ctx do
    assert {:error, :invalid} =
             Curriculum.log_teaching(ctx.scope_a, %{
               date: Date.utc_today(),
               content_taught: "Bogus",
               hours: Decimal.new("1"),
               progression_entry_id: ctx.entry_b.id
             })

    assert Curriculum.list_logs_for_plan!(ctx.entry_b.progression_plan_id, scope: ctx.scope_b) ==
             []
  end

  defp count_all(resource, tenant) do
    resource
    |> Ash.Query.for_read(:read)
    |> Ash.Query.set_tenant(tenant)
    |> Ash.count!()
  end
end
