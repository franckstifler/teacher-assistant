defmodule TeacherAssistantWeb.Configurations.TermLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/academic_years"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {@term.name}

        <:actions>
          <.button
            variant="primary"
            navigate={
              ~p"/configurations/academic_years/#{@term.academic_year_id}/terms/#{@term}/edit?return_to=show"
            }
          >
            <.icon name="hero-pencil-square" />{gettext("Edit Term")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("Name")}>
          {@term.name} {gettext("of")} {@term.academic_year.name}
        </:item>
        <:item title={gettext("Interval")}>{@term.start_date} - {@term.end_date}</:item>
      </.list>
      <div class="divider" />
      <h3 class="font-semibold text-2xl">{gettext("Sequences")}</h3>
      <div class="flex flex-wrap gap-x-4">
        <div :for={sequence <- @term.sequences} class="card card-sm bg-base-100 shadow flex-1">
          <.link href="#">
            <div class="card-body">
              <div class="card-title">{sequence.name}</div>
              <div>
                <p>{sequence.start_date} - {sequence.end_date}</p>
              </div>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"term_id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Term"))
     |> assign(
       :term,
       Ash.get!(TeacherAssistant.Academics.Term, id,
         load: [:academic_year, :sequences],
         scope: socket.assigns.scope
       )
     )}
  end
end
