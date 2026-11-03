defmodule TeacherAssistantWeb.Admin.AdminComponents do
  @moduledoc """
  Pieces shared by the operator console's screens: a school's status pill and the
  small uppercase panel title.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Accounts.SchoolVerificationStatus

  @doc """
  A school's status as a pill: « Suspendu » over its verification, « À vérifier »
  while unverified. `label` replaces the text (« Vérifié le 24 oct. »).
  """
  attr :id, :string, default: nil
  attr :status, :atom, required: true, doc: "the profile's verification status"
  attr :suspended, :boolean, default: false
  attr :label, :string, default: nil

  def school_status(assigns) do
    assigns = assign(assigns, :tone, if(assigns.suspended, do: :suspended, else: assigns.status))

    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold",
        status_class(@tone)
      ]}
    >
      {@label || status_label(@tone)}
    </span>
    """
  end

  defp status_class(:suspended), do: "bg-error/15 text-error"
  defp status_class(:verified), do: "bg-success/15 text-success"
  defp status_class(:unverified), do: "bg-warning/15 text-warning"
  defp status_class(_rejected), do: "bg-base-content/10 text-base-content/70"

  defp status_label(:suspended), do: gettext("Suspendu")
  defp status_label(:unverified), do: gettext("À vérifier")
  defp status_label(status), do: SchoolVerificationStatus.label(status)

  @doc "A panel's small uppercase title, as the console's mockups set it."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def panel_title(assigns) do
    ~H"""
    <h2 class={[
      "text-xs font-semibold uppercase tracking-[0.06em] text-base-content/70",
      @class
    ]}>
      {render_slot(@inner_block)}
    </h2>
    """
  end
end
