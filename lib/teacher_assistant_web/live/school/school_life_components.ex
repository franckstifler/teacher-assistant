defmodule TeacherAssistantWeb.School.SchoolLifeComponents do
  @moduledoc "Pieces shared by the surveillant's Aujourd'hui and Absences screens (spec G)."
  use TeacherAssistantWeb, :html

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
  def teacher_name(teacher), do: to_string(teacher.name || teacher.email)

  def hm(time), do: Calendar.strftime(time, "%H:%M")

  def periods_text(periods),
    do: Enum.map_join(periods, ", ", &"#{&1.label} (#{hm(&1.start_time)})")

  attr :row, :map, required: true

  def absence_status(assigns) do
    ~H"""
    <span :if={@row.justified?} class="badge badge-success badge-sm">
      {gettext("Justifiée · %{reason}", reason: JustificationReason.label(@row.reason))}
    </span>
    <span :if={not @row.justified?} class="badge badge-warning badge-sm">
      {gettext("Non justifiée")}
    </span>
    """
  end

  attr :row, :map, required: true

  def repeated_badge(assigns) do
    ~H"""
    <span :if={@row.flagged?} class="badge badge-error badge-sm">{gettext("Absences répétées")}</span>
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
        class="btn btn-outline btn-xs transition hover:btn-primary"
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
