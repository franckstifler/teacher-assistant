defmodule TeacherAssistantWeb.Configurations.SubjectLive.Index do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Listing Subjects")}
        <:actions>
          <.button variant="primary" navigate={~p"/configurations/subjects/new"}>
            <.icon name="hero-plus" /> {gettext("New Subject")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="subjects"
        rows={@streams.subjects}
        row_click={fn {_id, subject} -> JS.navigate(~p"/configurations/subjects/#{subject}") end}
      >
        <:col :let={{_id, subject}} label="Name">{subject.name}</:col>

        <:action :let={{_id, subject}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/subjects/#{subject}"}>{gettext("Show")}</.link>
          </div>

          <.link navigate={~p"/configurations/subjects/#{subject}/edit"}>{gettext("Edit")}</.link>
        </:action>

        <:action :let={{id, subject}}>
          <.link
            phx-click={JS.push("delete", value: %{id: subject.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            {gettext("Delete")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Listing Subjects"))
     |> stream(
       :subjects,
       Ash.read!(TeacherAssistant.Academics.Subject, scope: socket.assigns.scope)
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    subject = Ash.get!(TeacherAssistant.Academics.Subject, id, scope: socket.assigns.scope)
    Ash.destroy!(subject, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :subjects, subject)}
  end
end
