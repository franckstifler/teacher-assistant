defmodule TeacherAssistantWeb.School.SchoolLifeComponents do
  @moduledoc "Pieces shared by the surveillant's Aujourd'hui and Absences screens (spec G)."
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.JustificationReason

  @doc "Justifies the day of the absence row `row_id` (one of `rows`) for `reason` (a string)."
  def justify(scope, rows, row_id, reason) do
    case Enum.find(rows, &(&1.id == row_id)) do
      nil -> {:error, :invalid}
      row -> Attendance.justify_day(scope, row.enrollment, row.date, parse_reason(reason))
    end
  end

  defp parse_reason(value),
    do: Enum.find(JustificationReason.values(), &(Atom.to_string(&1) == value))

  def teacher_name(nil), do: "—"
  def teacher_name(teacher), do: User.display_name(teacher)

  def hm(time), do: Calendar.strftime(time, "%H:%M")

  @doc ~S|"Cours 1, Cours 2 · 1 h 50": the periods missed and their total length.|
  def periods_text(periods),
    do: "#{Enum.map_join(periods, ", ", & &1.label)} · #{duration(periods)}"

  defp duration(periods) do
    minutes = Enum.sum_by(periods, &div(Time.diff(&1.end_time, &1.start_time), 60))

    case {div(minutes, 60), rem(minutes, 60)} do
      {0, m} -> "#{m} min"
      {h, 0} -> "#{h} h"
      {h, m} -> "#{h} h #{String.pad_leading(to_string(m), 2, "0")}"
    end
  end

  @doc ~S|"Justifiée · Maladie" ("Motif non précisé" for older justifications).|
  def justified_label(row),
    do: gettext("Justifiée · %{reason}", reason: JustificationReason.label(row.reason))

  attr :row, :map, required: true

  def absence_status(assigns) do
    ~H"""
    <span
      :if={@row.justified?}
      class="ta-num flex-none rounded-full bg-primary/30 px-2 py-[3px] text-[0.68rem] font-semibold text-primary"
    >
      {justified_label(@row)}
    </span>
    <span
      :if={not @row.justified?}
      class="ta-num flex-none rounded-full bg-warning/25 px-2 py-[3px] text-[0.68rem] font-semibold text-warning"
    >
      {gettext("Non justifiée")}
    </span>
    """
  end

  attr :row, :map, required: true

  def repeated_badge(assigns) do
    ~H"""
    <span
      :if={@row.flagged?}
      class="ta-num rounded-full bg-error/20 px-1.5 py-px text-[0.62rem] font-semibold text-error"
    >
      {gettext("Absences répétées")}
    </span>
    """
  end

  attr :row, :map, required: true

  def overdue_badge(assigns) do
    ~H"""
    <span
      :if={@row.overdue?}
      class="ta-num rounded-full bg-warning/20 px-1.5 py-px text-[0.62rem] font-semibold text-warning"
    >
      {gettext("Délai dépassé")}
    </span>
    """
  end

  attr :row, :map, required: true

  def reason_chips(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <button
        :for={reason <- JustificationReason.values()}
        id={"justify-#{@row.id}-#{reason}"}
        type="button"
        class="cursor-pointer rounded-full border border-primary px-3 py-1.5 text-[0.76rem] font-semibold text-primary transition-colors hover:bg-primary/15"
        phx-click="justify"
        phx-value-row={@row.id}
        phx-value-reason={reason}
      >
        {JustificationReason.label(reason)}
      </button>
    </div>
    """
  end
end
