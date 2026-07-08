defmodule TeacherAssistant.Academics.AttendanceTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, cg_other} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})

    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})

    {:ok, _student1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, _student2} = Academics.add_student(cg, %{full_name: "Bilal", sex: :m})

    {:ok, _other_student} = Academics.add_student(cg_other, %{full_name: "Zara", sex: :f})

    roster = Academics.list_roster(cg)
    [%{enrollment: enrollment1}, %{enrollment: enrollment2}] = roster

    other_roster = Academics.list_roster(cg_other)
    [%{enrollment: other_enrollment}] = other_roster

    :ok = Timetables.build_default_periods(ws)
    period = Timetables.list_periods(ws) |> Enum.find(&(&1.kind == :lesson))

    other_period =
      Timetables.list_periods(ws) |> Enum.find(&(&1.kind == :lesson and &1.id != period.id))

    # 2025-09-15 is a Monday
    {:ok, slot} =
      Timetables.place_slot(cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    %{
      head: head,
      ws: ws,
      year: year,
      cg: cg,
      cg_other: cg_other,
      tc: tc,
      enrollment1: enrollment1,
      enrollment2: enrollment2,
      other_enrollment: other_enrollment,
      period: period,
      other_period: other_period,
      slot: slot
    }
  end

  describe "slot_for/3" do
    test "returns the placed slot with teaching_context loaded for a matching weekday", ctx do
      assert {:ok, %TimetableSlot{} = slot} =
               Attendance.slot_for(ctx.cg, ~D[2025-09-15], ctx.period.id)

      assert slot.id == ctx.slot.id
      assert slot.teaching_context.id == ctx.tc.id
    end

    test "returns {:error, :no_slot} for a day with no placed slot", ctx do
      # 2025-09-16 is a Tuesday, no slot placed there
      assert {:error, :no_slot} = Attendance.slot_for(ctx.cg, ~D[2025-09-16], ctx.period.id)
    end

    test "returns {:error, :no_slot} for a Sunday date", ctx do
      # 2025-09-14 is a Sunday
      assert {:error, :no_slot} = Attendance.slot_for(ctx.cg, ~D[2025-09-14], ctx.period.id)
    end
  end

  describe "period_roll/3 and record_period/6" do
    test "roll starts blank for every roster student", ctx do
      roll = Attendance.period_roll(ctx.cg, ctx.period, ~D[2025-09-15])

      assert roll.teaching_context.id == ctx.tc.id

      assert Enum.map(roll.students, & &1.status) == [nil, nil]
      names = Enum.map(roll.students, & &1.student_name)
      assert "Awa" in names
      assert "Bilal" in names
    end

    test "record_period marks a subset, leaving the rest nil", ctx do
      marks = [{ctx.enrollment1.id, :present}, {ctx.enrollment2.id, :absent}]

      assert {:ok, 2} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )

      roll = Attendance.period_roll(ctx.cg, ctx.period, ~D[2025-09-15])
      statuses = Map.new(roll.students, &{&1.enrollment_id, &1.status})

      assert statuses[ctx.enrollment1.id] == :present
      assert statuses[ctx.enrollment2.id] == :absent
    end

    test "record_period upserts instead of duplicating a mark", ctx do
      marks1 = [{ctx.enrollment1.id, :present}]
      marks2 = [{ctx.enrollment1.id, :late}]

      assert {:ok, 1} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks1,
                 ctx.head.id
               )

      assert {:ok, 1} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks2,
                 ctx.head.id
               )

      roll = Attendance.period_roll(ctx.cg, ctx.period, ~D[2025-09-15])
      statuses = Map.new(roll.students, &{&1.enrollment_id, &1.status})
      assert statuses[ctx.enrollment1.id] == :late

      assert AttendanceEntry
             |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id)
             |> Ash.read!(authorize?: false)
             |> length() == 1
    end

    test "record_period rejects an enrollment_id from another class", ctx do
      marks = [{ctx.other_enrollment.id, :present}]

      assert {:error, _} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )
    end

    test "record_period rejects an invalid status atom", ctx do
      marks = [{ctx.enrollment1.id, :tardy}]

      assert {:error, _} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )
    end

    test "record_period returns a clean tagged atom (not a raw Ash error) when the write fails",
         ctx do
      # validate_marks/2 only checks enrollment membership and status, not
      # teaching_context — so a teaching_context with a non-existent id
      # passes validation but trips the DB foreign-key constraint on write.
      bogus_tc = %TeacherAssistant.Academics.TeachingContext{id: Ecto.UUID.generate()}
      marks = [{ctx.enrollment1.id, :present}]

      assert {:error, :record_failed} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 bogus_tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )
    end
  end

  describe "class_register/2" do
    test "returns only lesson periods and every roster student with a cells map", ctx do
      marks = [{ctx.enrollment1.id, :present}, {ctx.enrollment2.id, :absent}]

      assert {:ok, 2} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )

      register = Attendance.class_register(ctx.cg, ~D[2025-09-15])

      assert Enum.all?(register.periods, &(&1.kind == :lesson))
      refute Enum.any?(register.periods, &(&1.kind == :break))

      assert length(register.students) == 2

      names = Enum.map(register.students, & &1.student_name)
      assert "Awa" in names
      assert "Bilal" in names

      student1 = Enum.find(register.students, &(&1.enrollment_id == ctx.enrollment1.id))
      student2 = Enum.find(register.students, &(&1.enrollment_id == ctx.enrollment2.id))

      assert student1.cells[ctx.period.id] == :present
      assert student2.cells[ctx.period.id] == :absent

      # other_period has no slot/marks for this day -> nil cell
      assert student1.cells[ctx.other_period.id] == nil
    end
  end

  describe "justify_day/3 and unjustify_day/2" do
    test "justify_day flips only that day's absent entries, leaving others untouched", ctx do
      marks = [{ctx.enrollment1.id, :absent}, {ctx.enrollment2.id, :present}]

      assert {:ok, 2} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )

      assert {:ok, 1} = Attendance.justify_day(ctx.enrollment1, ~D[2025-09-15], "Sick note")

      entry1 =
        AttendanceEntry
        |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id and date == ^~D[2025-09-15])
        |> Ash.read_one!(authorize?: false)

      entry2 =
        AttendanceEntry
        |> Ash.Query.filter(enrollment_id == ^ctx.enrollment2.id and date == ^~D[2025-09-15])
        |> Ash.read_one!(authorize?: false)

      assert entry1.justified == true
      assert entry1.justification_note == "Sick note"

      # non-absent entry untouched
      assert entry2.justified == false
      assert entry2.justification_note == nil
    end

    test "justify_day accepts a bare enrollment_id", ctx do
      marks = [{ctx.enrollment1.id, :absent}]

      assert {:ok, 1} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )

      assert {:ok, 1} = Attendance.justify_day(ctx.enrollment1.id, ~D[2025-09-15], "Note")

      entry1 =
        AttendanceEntry
        |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id and date == ^~D[2025-09-15])
        |> Ash.read_one!(authorize?: false)

      assert entry1.justified == true
      assert entry1.justification_note == "Note"
    end

    test "justify_day does not touch absent entries on other dates", ctx do
      # place a second slot on the other period, same day, to get two absences
      # but we only need a distinct date entry: seed via record_period on a
      # different period id, same enrollment. AttendanceEntry identity is
      # {enrollment_id, date, period_id}, so a different period on the same
      # date is a different row — use it to prove date-scoping still narrows
      # correctly against a *different date* below.
      marks = [{ctx.enrollment1.id, :absent}]

      assert {:ok, 1} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )

      # 2025-09-22 is also a Monday; seed an absence there directly via :record
      {:ok, other_day_entry} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: ~D[2025-09-22],
          status: :absent,
          enrollment_id: ctx.enrollment1.id,
          period_id: ctx.period.id,
          teaching_context_id: ctx.tc.id,
          recorded_by_user_id: ctx.head.id,
          workspace_id: ctx.ws.id
        })
        |> Ash.create(authorize?: false)

      assert {:ok, 1} = Attendance.justify_day(ctx.enrollment1, ~D[2025-09-15], "Note")

      other_day_entry = Ash.get!(AttendanceEntry, other_day_entry.id, authorize?: false)
      assert other_day_entry.justified == false
      assert other_day_entry.justification_note == nil
    end

    test "unjustify_day reverses justify_day", ctx do
      marks = [{ctx.enrollment1.id, :absent}]

      assert {:ok, 1} =
               Attendance.record_period(
                 ctx.cg,
                 ctx.period,
                 ctx.tc,
                 ~D[2025-09-15],
                 marks,
                 ctx.head.id
               )

      assert {:ok, 1} = Attendance.justify_day(ctx.enrollment1, ~D[2025-09-15], "Sick note")
      assert {:ok, 1} = Attendance.unjustify_day(ctx.enrollment1, ~D[2025-09-15])

      entry1 =
        AttendanceEntry
        |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id and date == ^~D[2025-09-15])
        |> Ash.read_one!(authorize?: false)

      assert entry1.justified == false
      assert entry1.justification_note == nil
    end
  end

  describe "student_conduct/2 and class_conduct/2" do
    setup ctx do
      :ok = Academics.build_default_calendar(ctx.year)

      [seq1, seq2 | _] = Academics.list_sequences(ctx.year)
      [term1 | _] = Academics.list_terms(ctx.year)

      %{seq1: seq1, seq2: seq2, term1: term1}
    end

    test "sums justified/unjustified hours and retards within a séquence, excluding entries outside it",
         ctx do
      %{seq1: seq1, period: period, tc: tc, enrollment1: enrollment1, ws: ws, head: head} = ctx

      in_range_date = seq1.start_date
      outside_date = Date.add(seq1.end_date, 30)

      # Inside the séquence: one justified absence, one late.
      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: in_range_date,
          status: :absent,
          justified: true,
          enrollment_id: enrollment1.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: in_range_date,
          status: :late,
          enrollment_id: enrollment1.id,
          period_id: ctx.other_period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      # Outside the séquence: must be excluded entirely.
      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: outside_date,
          status: :absent,
          justified: false,
          enrollment_id: enrollment1.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      totals = Attendance.student_conduct(enrollment1, {:sequence, seq1})

      expected_hours =
        Decimal.div(
          Decimal.new(Time.diff(period.end_time, period.start_time, :minute)),
          Decimal.new(60)
        )

      assert Decimal.equal?(totals.justified_hours, expected_hours)
      assert Decimal.equal?(totals.unjustified_hours, Decimal.new(0))
      assert totals.retards == 1
    end

    test "student_conduct accepts a bare enrollment_id", ctx do
      %{seq1: seq1, period: period, tc: tc, enrollment1: enrollment1, ws: ws, head: head} = ctx

      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: seq1.start_date,
          status: :absent,
          justified: false,
          enrollment_id: enrollment1.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      totals = Attendance.student_conduct(enrollment1.id, {:sequence, seq1})

      expected_hours =
        Decimal.div(
          Decimal.new(Time.diff(period.end_time, period.start_time, :minute)),
          Decimal.new(60)
        )

      assert Decimal.equal?(totals.unjustified_hours, expected_hours)
    end

    test "trimester total covers both of its séquences", ctx do
      %{term1: term1, period: period, tc: tc, enrollment1: enrollment1, ws: ws, head: head} = ctx

      [seq1, seq2 | _] = term1.sequences

      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: seq1.start_date,
          status: :absent,
          justified: true,
          enrollment_id: enrollment1.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: seq2.start_date,
          status: :absent,
          justified: false,
          enrollment_id: enrollment1.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      totals = Attendance.student_conduct(enrollment1, {:trimester, term1})

      expected_hours =
        Decimal.div(
          Decimal.new(Time.diff(period.end_time, period.start_time, :minute)),
          Decimal.new(60)
        )

      assert Decimal.equal?(totals.justified_hours, expected_hours)
      assert Decimal.equal?(totals.unjustified_hours, expected_hours)
    end

    test "returns zeros when the period date range is nil", ctx do
      empty_year_head = TeacherFixtures.user_fixture()
      {:ok, empty_ws} = Schools.create_school(empty_year_head, %{name: "Lycée Empty"})

      {:ok, empty_year} =
        Academics.create_academic_year(empty_ws, %{
          name: "2099-2100",
          start_date: ~D[2099-09-08],
          end_date: ~D[2100-07-31],
          active: false
        })

      # no sequences built for this year -> {:annual, empty_year} resolves to nil range
      totals = Attendance.student_conduct(ctx.enrollment1, {:annual, empty_year})

      assert Decimal.equal?(totals.justified_hours, Decimal.new(0))
      assert Decimal.equal?(totals.unjustified_hours, Decimal.new(0))
      assert totals.retards == 0
    end

    test "class_conduct returns per-student totals keyed by enrollment_id for the whole roster",
         ctx do
      %{
        seq1: seq1,
        period: period,
        tc: tc,
        enrollment1: enrollment1,
        enrollment2: enrollment2,
        ws: ws,
        head: head,
        cg: cg
      } = ctx

      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: seq1.start_date,
          status: :absent,
          justified: true,
          enrollment_id: enrollment1.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      {:ok, _} =
        AttendanceEntry
        |> Ash.Changeset.for_create(:record, %{
          date: seq1.start_date,
          status: :late,
          enrollment_id: enrollment2.id,
          period_id: period.id,
          teaching_context_id: tc.id,
          recorded_by_user_id: head.id,
          workspace_id: ws.id
        })
        |> Ash.create(authorize?: false)

      results = Attendance.class_conduct(cg, {:sequence, seq1})

      expected_hours =
        Decimal.div(
          Decimal.new(Time.diff(period.end_time, period.start_time, :minute)),
          Decimal.new(60)
        )

      assert Decimal.equal?(results[enrollment1.id].justified_hours, expected_hours)
      assert results[enrollment2.id].retards == 1
      # enrollment2 has no absence entries -> zero hours
      assert Decimal.equal?(results[enrollment2.id].justified_hours, Decimal.new(0))
      assert Decimal.equal?(results[enrollment2.id].unjustified_hours, Decimal.new(0))
    end

    test "class_conduct includes roster enrollments with no entries as zero totals", ctx do
      %{seq1: seq1, cg: cg, enrollment1: enrollment1, enrollment2: enrollment2} = ctx

      results = Attendance.class_conduct(cg, {:sequence, seq1})

      assert map_size(results) == 2
      assert Decimal.equal?(results[enrollment1.id].justified_hours, Decimal.new(0))
      assert Decimal.equal?(results[enrollment2.id].unjustified_hours, Decimal.new(0))
      assert results[enrollment1.id].retards == 0
    end

    test "class_conduct returns zeros for every roster enrollment when the range is nil", ctx do
      empty_year_head = TeacherFixtures.user_fixture()
      {:ok, empty_ws} = Schools.create_school(empty_year_head, %{name: "Lycée Empty2"})

      {:ok, empty_year} =
        Academics.create_academic_year(empty_ws, %{
          name: "2099-2100",
          start_date: ~D[2099-09-08],
          end_date: ~D[2100-07-31],
          active: false
        })

      results = Attendance.class_conduct(ctx.cg, {:annual, empty_year})

      assert map_size(results) == 2
      assert Decimal.equal?(results[ctx.enrollment1.id].justified_hours, Decimal.new(0))
      assert Decimal.equal?(results[ctx.enrollment2.id].unjustified_hours, Decimal.new(0))
    end
  end
end
