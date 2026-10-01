defmodule TeacherAssistant.Academics.HolidaysTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Attendance, Organization}
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    year = TeacherFixtures.complete_school_setup!(scope)
    %{scope: %{scope | current_academic_year: year}, year: year}
  end

  test "creating a year prefills the national holidays inside it", %{scope: scope, year: year} do
    labels = scope |> Organization.list_holidays(year) |> Enum.map(& &1.label)
    assert "Noël" in labels
    assert "Fête nationale" in labels
    assert length(labels) == 7
  end

  test "Préremplir adds nothing twice", %{scope: scope, year: year} do
    assert {:ok, 0} = Organization.prefill_holidays(scope, year)
    [first | _] = Organization.list_holidays(scope, year)
    :ok = Organization.delete_holiday(scope, first)
    assert {:ok, 1} = Organization.prefill_holidays(scope, year)
    assert length(Organization.list_holidays(scope, year)) == 7
  end

  test "a holiday ends on or after its start, inside the year", %{scope: scope, year: year} do
    assert {:ok, h} =
             Organization.create_holiday(scope, year, %{
               label: "Congés de Noël",
               start_date: ~D[2025-12-19],
               end_date: ~D[2026-01-04]
             })

    assert h.label == "Congés de Noël"

    for {s, e} <- [{~D[2025-12-20], ~D[2025-12-19]}, {~D[2025-09-01], ~D[2025-09-02]}, {~D[2026-07-30], ~D[2026-08-02]}] do
      assert {:error, %Ash.Error.Invalid{}} =
               Organization.create_holiday(scope, year, %{label: "X", start_date: s, end_date: e})
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Organization.create_holiday(scope, year, %{label: " ", start_date: ~D[2025-10-01], end_date: ~D[2025-10-01]})
  end

  test "school_calendar combines the profile and the active year's holidays", %{scope: scope} do
    cal = Attendance.school_calendar(scope)
    assert cal.lesson_days == SchoolCalendar.all_days()
    refute cal.wednesday_afternoon_off?
    refute SchoolCalendar.lesson_day?(cal, ~D[2025-12-25])
    assert SchoolCalendar.lesson_day?(cal, ~D[2025-12-24])
  end

  test "profile defaults", %{scope: scope} do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert profile.lesson_days == nil
    assert profile.default_lesson_minutes == 50
    refute profile.wednesday_afternoon_off?
  end

  test "a plain teacher cannot add a holiday", %{scope: scope, year: year} do
    teacher = %{TeacherFixtures.member_scope_fixture(scope) | current_academic_year: year}

    assert {:error, %Ash.Error.Forbidden{}} =
             Organization.create_holiday(teacher, year, %{label: "X", start_date: ~D[2025-10-01], end_date: ~D[2025-10-01]})
  end
end
