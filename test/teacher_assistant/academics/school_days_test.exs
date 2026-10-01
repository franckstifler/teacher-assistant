defmodule TeacherAssistant.Academics.SchoolDaysTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    :ok = Attendance.build_default_periods(scope)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e J", level: "6ème"})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(2)})

    periods = Attendance.list_periods(scope)
    %{scope: scope, year: year, cg: cg, tc: tc, periods: periods}
  end

  defp lesson(periods, label), do: Enum.find(periods, &(&1.label == label))

  test "the default schedule has 50-minute lessons and breaks at 10:00 and 13:00", %{
    periods: periods
  } do
    lessons = Enum.filter(periods, &(&1.kind == :lesson))
    assert length(lessons) == 9
    assert Enum.all?(lessons, &(Time.diff(&1.end_time, &1.start_time, :minute) == 50))
    assert %{start_time: ~T[10:00:00], end_time: ~T[10:15:00]} = lesson(periods, "Récréation")
    assert %{start_time: ~T[13:00:00], end_time: ~T[13:30:00]} = lesson(periods, "Pause")
  end

  test "periods may not overlap or end before they start", %{scope: scope} do
    assert {:error, %Ash.Error.Invalid{}} =
             Attendance.create_period(scope, %{
               position: 20,
               label: "X",
               start_time: ~T[08:00:00],
               end_time: ~T[08:30:00],
               kind: :lesson
             })

    assert {:error, %Ash.Error.Invalid{}} =
             Attendance.create_period(scope, %{
               position: 20,
               label: "X",
               start_time: ~T[17:00:00],
               end_time: ~T[16:30:00],
               kind: :lesson
             })

    assert {:ok, _} =
             Attendance.create_period(scope, %{
               position: 20,
               label: "Cours 10",
               start_time: ~T[16:00:00],
               end_time: ~T[16:50:00],
               kind: :lesson
             })
  end

  test "saves lesson days, the Wednesday toggle and the lesson length", %{scope: scope} do
    assert {:ok, profile} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ~w(monday tuesday wednesday thursday friday),
               "wednesday_afternoon_off?" => "true",
               "default_lesson_minutes" => "45"
             })

    assert profile.lesson_days == ~w(monday tuesday wednesday thursday friday)a
    assert profile.wednesday_afternoon_off?
    assert profile.default_lesson_minutes == 45
  end

  test "closing a day or Wednesday afternoon that holds lessons is refused", ctx do
    %{scope: scope, cg: cg, tc: tc, periods: periods} = ctx

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :saturday,
        period_id: lesson(periods, "Cours 1").id,
        teaching_context_id: tc.id
      })

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :wednesday,
        period_id: lesson(periods, "Cours 7").id,
        teaching_context_id: tc.id
      })

    assert {:error, {:slots_in_closed_cells, [saturday: 1]}} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ~w(monday tuesday wednesday thursday friday),
               "default_lesson_minutes" => "50"
             })

    assert {:error, {:slots_in_closed_cells, [wednesday: 1]}} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ~w(monday tuesday wednesday thursday friday saturday),
               "wednesday_afternoon_off?" => "true",
               "default_lesson_minutes" => "50"
             })

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert profile.lesson_days == nil
  end

  test "only the active year's slots block a change", ctx do
    %{scope: scope, cg: cg, tc: tc, periods: periods} = ctx

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :saturday,
        period_id: lesson(periods, "Cours 1").id,
        teaching_context_id: tc.id
      })

    {:ok, next} =
      Organization.create_academic_year(scope, %{
        name: "2026-2027",
        start_date: ~D[2026-09-07],
        end_date: ~D[2027-07-30]
      })

    {:ok, _} = Organization.activate_academic_year(scope, next)
    scope = %{scope | current_academic_year: next}

    assert {:ok, _} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ~w(monday tuesday),
               "default_lesson_minutes" => "50"
             })
  end

  test "unknown days, no day, or a bad length are refused", %{scope: scope} do
    assert {:error, :invalid_setting} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ["sunday"],
               "default_lesson_minutes" => "50"
             })

    assert {:error, :invalid_setting} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => [""],
               "default_lesson_minutes" => "50"
             })

    assert {:error, :invalid_setting} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ["monday"],
               "default_lesson_minutes" => "x"
             })
  end
end
