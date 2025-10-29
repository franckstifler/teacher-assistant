defmodule TeacherAssistantWeb.Configurations.TermLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.button navigate={~p"/configurations/terms"}>
          <.icon name="hero-arrow-left" />
        </.button>
        {@term.name}

        <:actions>
          <.button variant="primary" navigate={~p"/configurations/terms/#{@term}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" />{gettext("Edit term")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title={gettext("Name")}>{@term.name}</:item>
        <:item title={gettext("Start Date")}>{@term.start_date}</:item>
        <:item title={gettext("End Date")}>{@term.end_date}</:item>
        <:item title={gettext("Sequences")}>
          <ul>
            <%= for sequence <- @term.sequences do %>
              <li>{sequence.name} ({sequence.start_date} - {sequence.end_date})</li>
            <% end %>
          </ul>
        </:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Term"))
     |> assign(
       :term,
       Ash.get!(TeacherAssistant.Academics.Term, id,
         load: [:sequences],
         scope: socket.assigns.scope
       )
     )}
  end
end
