defmodule TeacherAssistantWeb.TeachingNav do
  @moduledoc """
  The one way around a teacher's class pages (UI review 2026-10-14, habit 12):
  the breadcrumb « Mes cours / course » back to the course list, then
  Notes · Résultats · Élèves for the course on screen. Replaces the rail's class
  switcher and per-class menu.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: TeacherAssistantWeb.Endpoint,
    router: TeacherAssistantWeb.Router,
    statics: TeacherAssistantWeb.static_paths()

  import TeacherAssistantWeb.CoreComponents, only: [breadcrumb: 1]

  attr :context_id, :string, required: true
  attr :label, :string, required: true, doc: "the course on screen, « Mathématiques · 2nde A »"
  attr :current, :atom, required: true, values: [:marks, :summary, :roster]

  def teaching_nav(assigns) do
    assigns =
      assign(assigns, :tabs, [
        {:marks, gettext("Notes"), ~p"/teacher/contexts/#{assigns.context_id}/marks"},
        {:summary, gettext("Résultats"),
         ~p"/teacher/contexts/#{assigns.context_id}/marks/summary"},
        {:roster, gettext("Élèves"), ~p"/teacher/contexts/#{assigns.context_id}/roster"}
      ])

    ~H"""
    <.breadcrumb>
      <:crumb id="teaching-nav-back" navigate={~p"/school/courses"}>{gettext("Mes cours")}</:crumb>
      <:crumb>{@label}</:crumb>
    </.breadcrumb>
    <nav id="teaching-nav" aria-label={gettext("Ce cours")} class="flex flex-wrap items-center gap-3">
      <div class="flex gap-1 rounded-box bg-base-200 p-1">
        <.link
          :for={{key, label, path} <- @tabs}
          id={"teaching-nav-#{key}"}
          navigate={path}
          aria-current={key == @current && "page"}
          class={[
            "min-h-9 rounded-[0.5rem] px-3 py-1.5 text-sm font-semibold transition-colors",
            if(key == @current,
              do: "bg-base-100 text-base-content shadow-sm",
              else: "text-base-content/70 hover:text-base-content"
            )
          ]}
        >
          {label}
        </.link>
      </div>
    </nav>
    """
  end
end
