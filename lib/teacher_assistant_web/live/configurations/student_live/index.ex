defmodule TeacherAssistantWeb.Configurations.StudentLive.Index do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Listing Students")}
        <:actions>
          <.button variant="primary" navigate={~p"/configurations/students/new"}>
            <.icon name="hero-plus" /> {gettext("New Student")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="students"
        rows={@streams.students}
        row_click={
          fn {_id, student} ->
            JS.navigate(~p"/configurations/students/#{student}")
          end
        }
      >
        <:col :let={{_id, student}} label={gettext("First name")}>
          {student.first_name}
        </:col>
        <:col :let={{_id, student}} label={gettext("Last name")}>
          {student.last_name}
        </:col>
        <:col :let={{_id, student}} label={gettext("Matricule")}>
          {student.matricule}
        </:col>

        <:action :let={{_id, student}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/students/#{student}"}>
              {gettext("Show")}
            </.link>
          </div>

          <.link navigate={~p"/configurations/students/#{student}/edit"}>
            {gettext("Edit")}
          </.link>
        </:action>

        <:action :let={{id, student}}>
          <.link
            phx-click={JS.push("delete", value: %{id: student.id}) |> hide("##{id}")}
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
     |> assign(:page_title, gettext("Listing Students"))
     |> stream(:students, Ash.read!(TeacherAssistant.Academics.Student, scope: socket.assigns.scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    student = Ash.get!(TeacherAssistant.Academics.Student, id, scope: socket.assigns.scope)
    Ash.destroy!(student, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :students, student)}
  end
end
