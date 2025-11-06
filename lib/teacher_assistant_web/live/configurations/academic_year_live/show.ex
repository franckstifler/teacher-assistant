defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/academic_years"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {gettext("Academic Year")} {@academic_year.name}

        <:actions>
          <.button
            variant="primary"
            navigate={~p"/configurations/academic_years/#{@academic_year}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" />{gettext("Edit Academic Year")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@academic_year.name}</:item>
        <:item title="Description">{@academic_year.description}</:item>
      </.list>
      <div class="divider" />
      <h3 class="font-semibold text-2xl">{gettext("Terms")}</h3>
      <div class="flex flex-wrap gap-x-4">
        <div :for={term <- @academic_year.terms} class="card card-sm bg-base-100 shadow flex-1">
          <.link navigate={~p"/configurations/academic_years/#{@academic_year}/terms/#{term}"}>
            <div class="card-body">
              <div class="card-title">{term.name}</div>
              <div>
                <p>{term.start_date} - {term.end_date}</p>
              </div>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Academic Year"))
     |> assign(
       :academic_year,
       Ash.get!(TeacherAssistant.Academics.AcademicYear, id,
         load: [terms: [:sequences]],
         scope: socket.assigns.scope
       )
     )}
  end
end
