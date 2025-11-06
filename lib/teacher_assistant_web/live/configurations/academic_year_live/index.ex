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
        id="academic_years"
        rows={@streams.academic_years}
        row_click={
          fn {_id, academic_year} ->
            JS.navigate(~p"/configurations/academic_years/#{academic_year}")
          end
        }
      >
        <:col :let={{_id, academic_year}} label={gettext("Name")}>{academic_year.name}</:col>
        <:col :let={{_id, academic_year}} label={gettext("Active")}>{academic_year.active}</:col>

        <:action :let={{_id, academic_year}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/academic_years/#{academic_year}"}>
              {gettext("Show")}
            </.link>
          </div>

          <.link navigate={~p"/configurations/academic_years/#{academic_year}/edit"}>
            {gettext("Edit")}
          </.link>
        </:action>

        <:action :let={{id, academic_year}}>
          <.link
            phx-click={JS.push("delete", value: %{id: academic_year.id}) |> hide("##{id}")}
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
     |> assign(:page_title, gettext("Listing Academic Years"))
     |> stream(
       :academic_years,
       Ash.read!(TeacherAssistant.Academics.AcademicYear, scope: socket.assigns.scope)
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    academic_year =
      Ash.get!(TeacherAssistant.Academics.AcademicYear, id, scope: socket.assigns.scope)

    Ash.destroy!(academic_year, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :academic_years, academic_year)}
  end
end
