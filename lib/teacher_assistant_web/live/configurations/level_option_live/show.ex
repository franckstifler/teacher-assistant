defmodule TeacherAssistantWeb.Configurations.LevelOptionLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/levels_options"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {@level_option.full_name}

        <:actions></:actions>
      </.header>

      <.list>
        <:item title={gettext("Level")}>{@level_option.level.name}</:item>
        <:item title={gettext("Option")}>{@level_option.option.name}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Level"))
     |> assign(
       :level_option,
       Ash.get!(TeacherAssistant.Academics.LevelOption, id,
         load: [:full_name, :level, :option],
         scope: socket.assigns.scope
       )
     )}
  end
end
