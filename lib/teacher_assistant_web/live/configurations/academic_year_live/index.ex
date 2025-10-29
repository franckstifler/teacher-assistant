defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.Index do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Listing Academic Years")}
        <:actions>
          <.button variant="primary" navigate={~p"/configurations/academic_years/new"}>
            <.icon name="hero-plus" /> {gettext("New Academic Year")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="terms"
        rows={@streams.terms}
        row_click={fn {_id, term} -> JS.navigate(~p"/configurations/academic_years/#{term}") end}
      >
        <:col :let={{_id, term}} label={gettext("Name")}>{term.name}</:col>

        <:action :let={{_id, term}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/academic_years/#{term}"}>{gettext("Show")}</.link>
          </div>

          <.link patch={~p"/configurations/academic_years/#{term}/edit"}>{gettext("Edit")}</.link>
        </:action>

        <:action :let={{id, term}}>
          <.link
            phx-click={JS.push("delete", value: %{id: term.id}) |> hide("##{id}")}
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
    dbg(socket.assigns)

    {:ok,
     socket
     |> assign(:page_title, gettext("Listing Academic Years"))
     |> stream(
       :terms,
       Ash.read!(TeacherAssistant.Academics.AcademicYear, scope: socket.assigns.scope)
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    term = Ash.get!(TeacherAssistant.Academics.AcademicYear, id, scope: socket.assigns.scope)
    Ash.destroy!(term, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :terms, term)}
  end
end
