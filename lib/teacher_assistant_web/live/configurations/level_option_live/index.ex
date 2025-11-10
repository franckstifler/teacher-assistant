defmodule TeacherAssistantWeb.Configurations.LevelOptionLive.Index do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {gettext("Listing LevelsOptions")}
        <:subtitle>
          {gettext("Available classes and specialities in your institution")}
        </:subtitle>
      </.header>

      <.table
        id="levels_options"
        rows={@streams.levels_options}
        row_click={
          fn {_id, level_option} ->
            JS.navigate(~p"/configurations/levels_options/#{level_option}")
          end
        }
      >
        <:col :let={{_id, level_option}} label="Name">{level_option.full_name}</:col>

        <:action :let={{_id, level_option}}>
          <div class="sr-only">
            <.link navigate={~p"/configurations/levels_options/#{level_option}"}>
              {gettext("Show")}
            </.link>
          </div>
        </:action>

        <:action :let={{id, level_option}}>
          <.link
            phx-click={JS.push("delete", value: %{id: level_option.id}) |> hide("##{id}")}
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
     |> assign(:page_title, gettext("Listing Levels"))
     |> stream(
       :levels_options,
       Ash.read!(TeacherAssistant.Academics.LevelOption,
         load: [:full_name],
         scope: socket.assigns.scope
       )
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    level_option =
      Ash.get!(TeacherAssistant.Academics.LevelOption, id, scope: socket.assigns.scope)

    Ash.destroy!(level_option, scope: socket.assigns.scope)

    {:noreply, stream_delete(socket, :levels_options, level_option)}
  end
end
