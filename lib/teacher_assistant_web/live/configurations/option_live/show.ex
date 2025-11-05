defmodule TeacherAssistantWeb.Configurations.OptionLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/options"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {@option.name}

        <:actions>
          <.button
            variant="primary"
            navigate={~p"/configurations/options/#{@option}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" />{gettext("Edit option")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("Name")}>{@option.name}</:item>
        <:item title={gettext("Description")}>{@option.description}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Option"))
     |> assign(
       :option,
       Ash.get!(TeacherAssistant.Academics.Option, id, scope: socket.assigns.scope)
     )}
  end
end
