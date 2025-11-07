defmodule TeacherAssistantWeb.Configurations.SubjectLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/subjects"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {@subject.name}

        <:actions>
          <.button
            variant="primary"
            navigate={~p"/configurations/subjects/#{@subject}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" />{gettext("Edit subject")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("Name")}>{@subject.name}</:item>
        <:item title={gettext("Default coefficient")}>{@subject.default_coefficient}</:item>
        <:item title={gettext("Description")}>{@subject.description}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Subject"))
     |> assign(
       :subject,
       Ash.get!(TeacherAssistant.Academics.Subject, id, scope: socket.assigns.scope)
     )}
  end
end
