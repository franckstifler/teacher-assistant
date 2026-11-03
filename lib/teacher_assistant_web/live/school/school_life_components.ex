defmodule TeacherAssistantWeb.School.SchoolLifeComponents do
  @moduledoc "Pieces shared by the surveillant's Aujourd'hui and Absences screens (spec G)."
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.JustificationReason

  def teacher_name(nil), do: "—"
  def teacher_name(teacher), do: User.display_name(teacher)

  def hm(time), do: Calendar.strftime(time, "%H:%M")

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
  attr :reasons, :list, default: nil, doc: "the reasons offered (default: all of them)"
  attr :class, :any, default: nil

  @doc "One button per justification reason, each justifying the row's day at once."
  def reason_chips(assigns) do
    assigns = assign(assigns, :reasons, assigns.reasons || JustificationReason.values())

    ~H"""
    <div class={["flex flex-wrap gap-1.5", @class]}>
      <button
        :for={reason <- @reasons}
        id={"justify-#{@row.id}-#{reason}"}
        type="button"
        class="btn btn-outline btn-sm flex-1 sm:flex-none"
        phx-click="justify"
        phx-value-row={@row.id}
        phx-value-reason={reason}
      >
        {reason_label(reason)}
      </button>
    </div>
    """
  end

  # short labels for the row buttons (« Famille » for « Raison familiale »)
  defp reason_label(:famille), do: gettext("Famille")
  defp reason_label(:autre), do: gettext("Autre")
  defp reason_label(:convocation), do: gettext("Convocation")
  defp reason_label(reason), do: JustificationReason.label(reason)
end
