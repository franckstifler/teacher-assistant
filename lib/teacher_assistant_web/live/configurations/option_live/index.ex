defmodule TeacherAssistantWeb.Configurations.OptionLive.Index do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Listing Options")}
        <:actions>
          <.button variant="primary" navigate={~p"/configurations/options/new"}>
            <.icon name="hero-plus" /> {gettext("New Option")}
          </.button>
        </:actions>
      </.header>

      <.table
        id="options"
        rows={@streams.options}
        row_click={fn {_id, option} -> JS.navigate(~p"/configurations/options/#{option}") end}
      >
        <:col :let={{_id, option}} label="Name">{option.name}</:col>

        <:action :let={{_id, option}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/options/#{option}"}>{gettext("Show")}</.link>
          </div>

          <.link navigate={~p"/configurations/options/#{option}/edit"}>{gettext("Edit")}</.link>
        </:action>

        <:action :let={{id, option}}>
          <.link
            phx-click={JS.push("delete", value: %{id: option.id}) |> hide("##{id}")}
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
     |> assign(:page_title, gettext("Listing Options"))
     |> stream(:options, Ash.read!(TeacherAssistant.Academics.Option, scope: socket.assigns.scope))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    option = Ash.get!(TeacherAssistant.Academics.Option, id, scope: socket.assigns.scope)
    Ash.destroy!(option, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :options, option)}
  end
end
