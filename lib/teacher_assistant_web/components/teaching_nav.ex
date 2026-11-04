defmodule TeacherAssistantWeb.TeachingNav do
  @moduledoc """
  The one way around a teacher's class pages (UI review 2026-10-14, habit 12;
  UX refonte 2026-11-03): Notes · Résultats · Élèves for the course on screen.
  On phones a back arrow to « Mes cours » with the course's title, then underline
  tabs across the width; from `sm` the breadcrumb « Mes cours / course » and
  segmented tabs.
  """
  use Phoenix.Component
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: TeacherAssistantWeb.Endpoint,
    router: TeacherAssistantWeb.Router,
    statics: TeacherAssistantWeb.static_paths()

  import TeacherAssistantWeb.CoreComponents, only: [breadcrumb: 1, icon: 1]

  attr :context_id, :string, required: true
  attr :label, :string, required: true, doc: "the course on screen, « Mathématiques · 2nde A »"
  attr :current, :atom, required: true, values: [:marks, :summary, :roster]

  attr :crumbs, :boolean,
    default: true,
    doc: "false when the page draws its own header (the marks page's course picker)"

  def teaching_nav(assigns) do
    assigns =
      assign(assigns, :tabs, [
        {:marks, gettext("Notes"), ~p"/teacher/contexts/#{assigns.context_id}/marks"},
        {:summary, gettext("Résultats"),
         ~p"/teacher/contexts/#{assigns.context_id}/marks/summary"},
        {:roster, gettext("Élèves"), ~p"/teacher/contexts/#{assigns.context_id}/roster"}
      ])

    ~H"""
    <header :if={@crumbs} id="teaching-nav-phone" class="-mt-1 flex items-center gap-1.5 sm:hidden">
      <.link
        id="teaching-nav-back-arrow"
        navigate={~p"/school/courses"}
        aria-label={gettext("Retour à Mes cours")}
        class="btn btn-ghost btn-square -ml-2 shrink-0"
      >
        <.icon name="hero-arrow-left" class="size-5" />
      </.link>
      <p class="min-w-0 flex-1 truncate text-[1.05rem] font-semibold">{@label}</p>
    </header>
    <div :if={@crumbs} class="hidden sm:block">
      <.breadcrumb>
        <:crumb id="teaching-nav-back" navigate={~p"/school/courses"}>
          {gettext("Mes cours")}
        </:crumb>
        <:crumb>{@label}</:crumb>
      </.breadcrumb>
    </div>
    <nav
      id="teaching-nav"
      aria-label={gettext("Ce cours")}
      class="-mx-4 flex border-b border-base-300 sm:mx-0 sm:w-fit sm:gap-1 sm:rounded-box sm:border-0 sm:bg-base-200 sm:p-1"
    >
      <.link
        :for={{key, label, path} <- @tabs}
        id={"teaching-nav-#{key}"}
        navigate={path}
        aria-current={key == @current && "page"}
        class={[
          "grid h-11 flex-1 place-items-center border-b-2 text-sm font-semibold transition-colors",
          "sm:h-auto sm:min-h-9 sm:flex-none sm:rounded-[0.5rem] sm:border-b-0 sm:px-3 sm:py-1.5",
          if(key == @current,
            do: "border-primary text-base-content sm:bg-base-100 sm:shadow-sm",
            else: "border-transparent text-base-content/70 hover:text-base-content"
          )
        ]}
      >
        {label}
      </.link>
    </nav>
    """
  end
end
