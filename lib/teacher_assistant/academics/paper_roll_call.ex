defmodule TeacherAssistant.Academics.PaperRollCall do
  @moduledoc """
  Paper roll call (spec 2026-10-28), pure. A class on paper takes its roll call on a
  weekly sheet the surveillant types in; until the Monday after a lesson's week, a
  lesson not taken in the app is `:on_paper`, not `:missed`. A lesson marked « cours
  non assuré » is `:not_held`, whatever the class's mode. A taken roll call stays
  `:done`.
  """

  @doc "The school week (Monday, Saturday) holding `date`."
  def week(%Date{} = date) do
    monday = Date.beginning_of_week(date)
    {monday, Date.add(monday, 5)}
  end

  @doc "Whether `today` is still before the Monday after `lesson_date`'s week."
  def waiting?(%Date{} = lesson_date, %Date{} = today) do
    next_monday = Date.add(Date.beginning_of_week(lesson_date), 7)
    Date.before?(today, next_monday)
  end

  @doc "The Monday of the week to print or type in by default: this one, the next from Saturday on."
  def default_week(%Date{} = today) do
    monday = Date.beginning_of_week(today)
    if Date.day_of_week(today) >= 6, do: Date.add(monday, 7), else: monday
  end

  @doc """
  A lesson's state from its clock-and-entries status (`:done | :missed | :in_progress |
  :upcoming`), whether its class is on paper, whether it is marked not held, its date
  and today.
  """
  def state(:done, _paper?, _not_held?, _date, _today), do: :done
  def state(_status, _paper?, true, _date, _today), do: :not_held

  def state(:missed, true, false, date, today),
    do: if(waiting?(date, today), do: :on_paper, else: :missed)

  def state(status, _paper?, false, _date, _today), do: status
end
