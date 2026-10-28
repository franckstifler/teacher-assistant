defmodule TeacherAssistant.Workers.PaperSheetsOverdue do
  @moduledoc """
  Paper roll call (spec 2026-10-28 §4): every Monday morning, tells each school's
  Proviseur and Surveillant général which paper classes still have a past week of the
  term not typed in — one notice listing them, oldest week first, linking to the first
  sheet to type in. Nothing when every sheet is in.
  """
  use Oban.Worker, queue: :default, max_attempts: 2, unique: [period: 3600]

  alias TeacherAssistant.{Attendance, Enrollment, Notifications, Organization}
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Workers.MissedRollCalls
  alias TeacherAssistantWeb.Dates

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = Reference.now()
    MissedRollCalls.run(Workspaces.job_scopes(), &notify(&1, Reference.today(), now))
  end

  defp notify(%{current_academic_year: nil}, _today, _now), do: :ok

  defp notify(scope, today, now) do
    year = scope.current_academic_year
    last = Date.add(Date.beginning_of_week(today), -1)
    first = term_start(scope, year, today)

    overdue =
      if Date.compare(first, last) == :gt,
        do: [],
        else: overdue_weeks(scope, year, first, last, now)

    case overdue do
      [] ->
        :ok

      [{cg, monday} | _] ->
        Notifications.deliver(
          scope,
          :paper_sheets_overdue,
          MissedRollCalls.recipient_ids(scope),
          %{count: length(overdue), list: list(overdue)},
          "/school/classes/#{cg.id}/roll-sheet?week=#{monday}"
        )
    end
  end

  # {class, Monday} for each paper class's week holding a lesson still missed.
  defp overdue_weeks(scope, year, first, last, now) do
    for cg <- Enrollment.list_class_groups(scope, year),
        cg.paper_roll_call,
        monday <-
          scope
          |> Attendance.class_lessons(cg, first, last, now)
          |> Enum.filter(&(&1.status == :missed))
          |> Enum.map(&Date.beginning_of_week(&1.date))
          |> Enum.uniq() do
      {cg, monday}
    end
    |> Enum.sort_by(fn {cg, monday} -> {Date.to_gregorian_days(monday), cg.label} end)
  end

  defp list(overdue) do
    Enum.map_join(overdue, ", ", fn {cg, monday} ->
      # Stored in the notice's params, in the school's language, like `MissedRollCalls`' list.
      "#{cg.label} (sem. du #{Dates.day_month(monday)})"
    end)
  end

  # The current term's first day (its séquences' start), else the year's.
  defp term_start(scope, year, today) do
    scope
    |> Organization.list_terms(year)
    |> Enum.find_value(fn term ->
      case Organization.period_date_range(scope, {:trimester, term}) do
        {first, last} ->
          if Date.compare(first, today) != :gt and Date.compare(today, last) != :gt, do: first

        _ ->
          nil
      end
    end) || year.start_date
  end
end
