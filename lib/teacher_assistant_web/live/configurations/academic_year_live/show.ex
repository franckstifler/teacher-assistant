defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.button navigate={~p"/configurations/academic_years"}>
          <.icon name="hero-arrow-left" />
        </.button>
        Academic Year {@academic_year.name}

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
        <:item title="Terms">
          <ul class="list-disc list-inside">
            <%= for term <- @academic_year.terms do %>
              <li>
                <strong><%= term.name %></strong>: {term.start_date} - {term.end_date}
              </li>
            <% end %>
          </ul>
        </:item>
      </.list>
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
