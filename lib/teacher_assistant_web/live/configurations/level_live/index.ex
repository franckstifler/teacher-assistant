defmodule TeacherAssistantWeb.Configurations.LevelLive.Index do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Listing Levels")}
        <:actions>
          <.button variant="primary" navigate={~p"/configurations/levels/new"}>
            <.icon name="hero-plus" /> {gettext("New Level")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="levels"
        rows={@streams.levels}
        row_click={fn {_id, level} -> JS.navigate(~p"/configurations/levels/#{level}") end}
      >
        <:col :let={{_id, level}} label="Name">{level.name}</:col>

        <:action :let={{_id, level}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/levels/#{level}"}>{gettext("Show")}</.link>
          </div>

          <.link navigate={~p"/configurations/levels/#{level}/edit"}>{gettext("Edit")}</.link>
        </:action>

        <:action :let={{id, level}}>
          <.link
            phx-click={JS.push("delete", value: %{id: level.id}) |> hide("##{id}")}
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
    levels = TeacherAssistant.Academics.read_levels!(scope: socket.assigns.scope)
    {:ok,
     socket
     |> assign(:page_title, gettext("Listing Levels"))
     |> stream(:levels, levels)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    level = Ash.get!(TeacherAssistant.Academics.Level, id, scope: socket.assigns.scope)
    Ash.destroy!(level, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :levels, level)}
  end
end
