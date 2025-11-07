defmodule TeacherAssistantWeb.Configurations.LevelLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/levels"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {@level.name}

        <:actions>
          <.button
            variant="primary"
            navigate={~p"/configurations/levels/#{@level}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" />{gettext("Edit level")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("Name")}>{@level.name}</:item>
        <:item title={gettext("Description")}>{@level.description}</:item>
        <:item title={gettext("Options")}>
          <div class="flex gap-x-2 mt-2">
            <div :for={option <- @level.options} class="badge badge-soft badge-primary">
              {option.name}
            </div>
          </div>
        </:item>
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
       :level,
       Ash.get!(TeacherAssistant.Academics.Level, id,
         load: [:options],
         scope: socket.assigns.scope
       )
     )}
  end
end
