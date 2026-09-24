defmodule TeacherAssistant.Academics.AttendanceCombinedTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Organization.create_school(head, %{name: "Lycée Combiné"})

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, maco} = Enrollment.create_class_group(ws, year, %{label: "1ère MACO", level: "1ère"})
    {:ok, menu} = Enrollment.create_class_group(ws, year, %{label: "1ère MENU", level: "1ère"})

    {:ok, tc_maco} = Curriculum.assign_teacher(maco, head, %{subject: "Maths"})
    {:ok, tc_menu} = Curriculum.assign_teacher(menu, head, %{subject: "Maths"})

    {:ok, _s_maco} = Enrollment.add_student(maco, %{full_name: "Awa", sex: :f})
    {:ok, _s_menu} = Enrollment.add_student(menu, %{full_name: "Beti", sex: :f})

    [%{enrollment: enr_maco}] = Enrollment.list_roster(maco)
    [%{enrollment: enr_menu}] = Enrollment.list_roster(menu)

    {:ok, course} = Curriculum.combine_course([tc_maco, tc_menu])

    :ok = Attendance.build_default_periods(ws)
    period = Attendance.list_periods(ws) |> Enum.find(&(&1.kind == :lesson))

    # 2025-09-08 is a Monday. Only MACO's slot is placed at this period: the
    # teacher can only be physically timetabled in one class at a time, so a
    # combined course's members can't (yet — see the separate combined
    # timetable-slot work) both hold a slot in the same cell. MENU's roll
    # therefore resolves with no teaching_context, which is a legitimate
    # state `period_roll/3` already handles.
    {:ok, _slot_maco} =
      Timetabling.place_slot(maco, %{
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
        |> Ash.read_one!(tenant: ctx.ws.id, authorize?: false)

      entry_menu =
        AttendanceEntry
        |> Ash.Query.filter(
          enrollment_id == ^ctx.enr_menu.id and date == ^ctx.date and period_id == ^ctx.period.id
        )
        |> Ash.read_one!(tenant: ctx.ws.id, authorize?: false)

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
               |> Ash.read!(tenant: ctx.ws.id, authorize?: false)

      assert [] =
               AttendanceEntry
               |> Ash.Query.filter(enrollment_id == ^ctx.enr_menu.id)
               |> Ash.read!(tenant: ctx.ws.id, authorize?: false)
    end

    test "a genuine DB-level failure in the second group rolls back the first group's already-written entry",
         ctx do
      # `Attendance.record_combined_period/5` pre-validates status/enrollment
      # in plain Elixir before ever touching the DB, so it can never exercise
      # `AttendanceEntry`'s `:record_combined_period` action's own
      # `transaction? true` — every failure it can reach is caught before the
      # transaction opens. This test drives the action directly with a
      # `teaching_context_id` that doesn't exist (a real foreign-key
      # violation, `attendance_entries_teaching_context_id_fkey`), which only
      # fails once the DB is touched. MACO's group is entirely valid and
      # would insert first; MENU's group is the one that trips the FK. If
      # `transaction? true` didn't roll back, MACO's entry would survive.
      bogus_teaching_context_id = Ecto.UUID.generate()

      groups = [
        %{
          teaching_context_id: ctx.tc_maco.id,
          marks: [%{enrollment_id: ctx.enr_maco.id, status: :present}]
        },
        %{
          teaching_context_id: bogus_teaching_context_id,
          marks: [%{enrollment_id: ctx.enr_menu.id, status: :absent}]
        }
      ]

      assert {:error, _reason} =
               AttendanceEntry
               |> Ash.ActionInput.for_action(
                 :record_combined_period,
                 %{
                   period_id: ctx.period.id,
                   date: ctx.date,
                   recorded_by_user_id: ctx.head.id,
                   groups: groups
                 },
                 tenant: ctx.ws.id
               )
               |> Ash.run_action()

      assert [] =
               AttendanceEntry
               |> Ash.Query.filter(enrollment_id == ^ctx.enr_maco.id)
               |> Ash.read!(tenant: ctx.ws.id, authorize?: false)

      assert [] =
               AttendanceEntry
               |> Ash.Query.filter(enrollment_id == ^ctx.enr_menu.id)
               |> Ash.read!(tenant: ctx.ws.id, authorize?: false)
    end
  end
end
