defmodule TeacherAssistant.Academics.AttendanceCombinedTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Academics.Courses
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Combiné"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, maco} = Academics.create_class_group(ws, year, %{label: "1ère MACO", level: "1ère"})
    {:ok, menu} = Academics.create_class_group(ws, year, %{label: "1ère MENU", level: "1ère"})

    {:ok, tc_maco} = Assignments.assign(maco, head, %{subject: "Maths"})
    {:ok, tc_menu} = Assignments.assign(menu, head, %{subject: "Maths"})

    {:ok, _s_maco} = Academics.add_student(maco, %{full_name: "Awa", sex: :f})
    {:ok, _s_menu} = Academics.add_student(menu, %{full_name: "Beti", sex: :f})

    [%{enrollment: enr_maco}] = Academics.list_roster(maco)
    [%{enrollment: enr_menu}] = Academics.list_roster(menu)

    {:ok, course} = Courses.combine([tc_maco, tc_menu])

    :ok = Timetables.build_default_periods(ws)
    period = Timetables.list_periods(ws) |> Enum.find(&(&1.kind == :lesson))

    # 2025-09-08 is a Monday. Only MACO's slot is placed at this period: the
    # teacher can only be physically timetabled in one class at a time, so a
    # combined course's members can't (yet — see the separate combined
    # timetable-slot work) both hold a slot in the same cell. MENU's roll
    # therefore resolves with no teaching_context, which is a legitimate
    # state `period_roll/3` already handles.
    {:ok, _slot_maco} =
      Timetables.place_slot(maco, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_maco.id
      })

    %{
      head: head,
      ws: ws,
      course: course,
      maco: maco,
      menu: menu,
      tc_maco: tc_maco,
      tc_menu: tc_menu,
      enr_maco: enr_maco,
      enr_menu: enr_menu,
      period: period,
      date: ~D[2025-09-08]
    }
  end

  describe "combined_period_roll/3" do
    test "returns students from both member classes, grouped by class", ctx do
      groups = Attendance.combined_period_roll(ctx.course, ctx.period, ctx.date)

      assert length(groups) == 2

      maco_group = Enum.find(groups, &(&1.class_group.id == ctx.maco.id))
      menu_group = Enum.find(groups, &(&1.class_group.id == ctx.menu.id))

      assert Enum.map(maco_group.students, & &1.enrollment_id) == [ctx.enr_maco.id]
      assert Enum.map(menu_group.students, & &1.enrollment_id) == [ctx.enr_menu.id]

      assert maco_group.teaching_context.id == ctx.tc_maco.id
      assert menu_group.teaching_context == nil
    end
  end

  describe "record_combined_period/5" do
    test "an absence for the MENU student lands on MENU's enrollment, and the MACO student on theirs",
         ctx do
      marks = [{ctx.enr_maco.id, :present}, {ctx.enr_menu.id, :absent}]

      assert {:ok, 2} =
               Attendance.record_combined_period(
                 ctx.course,
                 ctx.period,
                 ctx.date,
                 marks,
                 ctx.head.id
               )

      entry_maco =
        AttendanceEntry
        |> Ash.Query.filter(
          enrollment_id == ^ctx.enr_maco.id and date == ^ctx.date and period_id == ^ctx.period.id
        )
        |> Ash.read_one!(authorize?: false)

      entry_menu =
        AttendanceEntry
        |> Ash.Query.filter(
          enrollment_id == ^ctx.enr_menu.id and date == ^ctx.date and period_id == ^ctx.period.id
        )
        |> Ash.read_one!(authorize?: false)

      assert entry_maco.status == :present
      assert entry_maco.teaching_context_id == ctx.tc_maco.id

      assert entry_menu.status == :absent
      assert entry_menu.teaching_context_id == nil
    end

    test "an invalid status for one class rolls back the whole combined session (MACO's valid mark included)",
         ctx do
      # MACO's mark is valid and would be written first (classes are grouped
      # alphabetically); MENU's status is bogus — the whole session must roll
      # back, so MACO's entry must not survive either.
      marks = [{ctx.enr_maco.id, :present}, {ctx.enr_menu.id, :on_fire}]

      assert {:error, :invalid_status} =
               Attendance.record_combined_period(
                 ctx.course,
                 ctx.period,
                 ctx.date,
                 marks,
                 ctx.head.id
               )

      assert [] =
               AttendanceEntry
               |> Ash.Query.filter(enrollment_id == ^ctx.enr_maco.id)
               |> Ash.read!(authorize?: false)

      assert [] =
               AttendanceEntry
               |> Ash.Query.filter(enrollment_id == ^ctx.enr_menu.id)
               |> Ash.read!(authorize?: false)
    end
  end
end
