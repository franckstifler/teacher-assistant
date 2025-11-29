defmodule TeacherAssistantWeb.Configurations.StudentLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/students"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {@student.first_name} {@student.last_name}

        <:actions>
          <.button
            variant="primary"
            navigate={~p"/configurations/students/#{@student}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" />{gettext("Edit Student")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("First name")}>
          {@student.first_name}
        </:item>
        <:item title={gettext("Last name")}>
          {@student.last_name}
        </:item>
        <:item title={gettext("Matricule")}>
          {@student.matricule}
        </:item>
        <:item title={gettext("Date of birth")}>
          {@student.date_of_birth}
        </:item>
        <:item title={gettext("Place of birth")}>
          {@student.place_of_birth}
        </:item>
        <:item title={gettext("Gender")}>
          {@student.gender}
        </:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Student"))
     |> assign(
       :student,
       Ash.get!(TeacherAssistant.Academics.Student, id, scope: socket.assigns.scope)
     )}
  end
end
