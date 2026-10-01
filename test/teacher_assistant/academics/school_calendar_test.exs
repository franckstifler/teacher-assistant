defmodule TeacherAssistant.Academics.SchoolCalendarTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.SchoolCalendar

  @noel %{label: "Congés de Noël", start_date: ~D[2025-12-19], end_date: ~D[2026-01-04]}

  test "nil lesson days means Monday to Saturday" do
    cal = SchoolCalendar.new(nil, false, [])
    assert cal.lesson_days == SchoolCalendar.all_days()
    assert SchoolCalendar.lesson_day?(cal, ~D[2025-09-20])
    refute SchoolCalendar.lesson_day?(cal, ~D[2025-09-21])
  end

  test "an unticked weekday is not a lesson day" do
    cal = SchoolCalendar.new([:monday, :tuesday, :wednesday, :thursday, :friday], false, [])
    refute SchoolCalendar.lesson_day?(cal, ~D[2025-09-20])
    assert SchoolCalendar.lesson_day?(cal, ~D[2025-09-19])
  end

  test "a holiday range is a day off on every date, both ends included" do
    cal = SchoolCalendar.new(nil, false, [@noel])

    for d <- [~D[2025-12-19], ~D[2025-12-25], ~D[2026-01-03], ~D[2026-01-04]] do
      refute SchoolCalendar.lesson_day?(cal, d)
      assert SchoolCalendar.holiday_on(cal, d) == @noel
    end

    assert SchoolCalendar.lesson_day?(cal, ~D[2026-01-05])
    assert SchoolCalendar.holiday_on(cal, ~D[2026-01-05]) == nil
  end

  test "Wednesday afternoon: periods from 13:00 close when the toggle is on" do
    off = SchoolCalendar.new(nil, true, [])
    on = SchoolCalendar.new(nil, false, [])
    late = %{start_time: ~T[13:00:00]}
    morning = %{start_time: ~T[11:55:00]}

    refute SchoolCalendar.open_cell?(off, :wednesday, late)
    assert SchoolCalendar.open_cell?(off, :wednesday, morning)
    assert SchoolCalendar.open_cell?(off, :thursday, late)
    assert SchoolCalendar.open_cell?(on, :wednesday, late)
  end

  test "a cell on an unticked day is closed" do
    cal = SchoolCalendar.new([:monday], false, [])
    refute SchoolCalendar.open_cell?(cal, :tuesday, %{start_time: ~T[08:00:00]})
  end

  test "Easter dates" do
    assert SchoolCalendar.easter(2026) == ~D[2026-04-05]
    assert SchoolCalendar.easter(2025) == ~D[2025-04-20]
    assert SchoolCalendar.easter(2027) == ~D[2027-03-28]
  end

  test "national holidays inside a school year" do
    list = SchoolCalendar.national_holidays(~D[2025-09-08], ~D[2026-07-31])
    dates = Enum.map(list, & &1.start_date)

    assert ~D[2025-12-25] in dates
    assert ~D[2026-01-01] in dates
    assert ~D[2026-02-11] in dates
    assert ~D[2026-04-03] in dates
    assert ~D[2026-05-01] in dates
    assert ~D[2026-05-14] in dates
    assert ~D[2026-05-20] in dates
    assert length(list) == 7
    assert Enum.all?(list, &(&1.start_date == &1.end_date))
    assert dates == Enum.sort(dates, Date)

    assert SchoolCalendar.national_holidays(~D[2026-01-02], ~D[2026-02-01]) == []
  end
end
