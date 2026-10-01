defmodule TeacherAssistant.Academics.SchoolCalendar do
  @moduledoc """
  The school calendar (spec J1, S02/S03), pure: which weekdays have lessons, whether
  Wednesday afternoon is free (every period starting at or after 13:00), and the
  year's holidays. Built by `TeacherAssistant.Attendance.school_calendar/1`.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @all_days ~w(monday tuesday wednesday thursday friday saturday)a
  @afternoon ~T[13:00:00]

  defstruct lesson_days: @all_days, wednesday_afternoon_off?: false, holidays: []

  def all_days, do: @all_days

  def new(lesson_days, wednesday_afternoon_off?, holidays) do
    %__MODULE__{
      lesson_days: if(lesson_days in [nil, []], do: @all_days, else: lesson_days),
      wednesday_afternoon_off?: wednesday_afternoon_off? == true,
      holidays: holidays
    }
  end

  @doc "The weekday atom of `date`, or nil on a Sunday."
  def weekday(%Date{} = date), do: Enum.at(@all_days ++ [nil], Date.day_of_week(date) - 1)

  def lesson_day?(%__MODULE__{} = cal, %Date{} = date),
    do: weekday(date) in cal.lesson_days and is_nil(holiday_on(cal, date))

  def holiday_on(%__MODULE__{holidays: holidays}, %Date{} = date) do
    Enum.find(holidays, fn h ->
      Date.compare(date, h.start_date) != :lt and Date.compare(date, h.end_date) != :gt
    end)
  end

  @doc "Whether a lesson may sit in this (weekday, period) cell of the weekly timetable."
  def open_cell?(%__MODULE__{} = cal, day, period) do
    day in cal.lesson_days and
      not (cal.wednesday_afternoon_off? and day == :wednesday and afternoon?(period))
  end

  def afternoon?(%{start_time: %Time{} = start}), do: Time.compare(start, @afternoon) != :lt

  @doc "Easter Sunday (anonymous Gregorian algorithm)."
  def easter(year) do
    a = rem(year, 19)
    b = div(year, 100)
    c = rem(year, 100)
    d = div(b, 4)
    e = rem(b, 4)
    f = div(b + 8, 25)
    g = div(b - f + 1, 3)
    h = rem(19 * a + b - d - g + 15, 30)
    i = div(c, 4)
    k = rem(c, 4)
    l = rem(32 + 2 * e + 2 * i - h - k, 7)
    m = div(a + 11 * h + 22 * l, 451)
    month = div(h + l - 7 * m + 114, 31)
    day = rem(h + l - 7 * m + 114, 31) + 1
    Date.new!(year, month, day)
  end

  @doc "The national holidays between `first` and `last`, one day each, labels in the current locale."
  def national_holidays(%Date{} = first, %Date{} = last) do
    first.year..last.year
    |> Enum.flat_map(fn y ->
      easter = easter(y)

      [
        {Date.new!(y, 1, 1), gettext("Jour de l'an")},
        {Date.new!(y, 2, 11), gettext("Fête de la Jeunesse")},
        {Date.add(easter, -2), gettext("Vendredi saint")},
        {Date.new!(y, 5, 1), gettext("Fête du Travail")},
        {Date.add(easter, 39), gettext("Ascension")},
        {Date.new!(y, 5, 20), gettext("Fête nationale")},
        {Date.new!(y, 12, 25), gettext("Noël")}
      ]
    end)
    |> Enum.filter(fn {d, _} -> Date.compare(d, first) != :lt and Date.compare(d, last) != :gt end)
    |> Enum.sort_by(fn {d, _} -> Date.to_gregorian_days(d) end)
    |> Enum.map(fn {d, label} -> %{label: label, start_date: d, end_date: d} end)
  end
end
