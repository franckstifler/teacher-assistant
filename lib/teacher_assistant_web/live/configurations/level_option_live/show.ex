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
      <div class="divider" />
      <div class="flex justify-between">
        <h3 class="text-xl font-semibold">{gettext("Subjects")}</h3>
        <.link
          class="btn btn-sm btn-soft btn-ghost"
          navigate={~p"/configurations/levels_options/#{@level_option}/manage_subjects"}
        >
          <.icon name="hero-pencil-square" />{gettext("Manage Subjects")}
        </.link>
      </div>
      <table class="table table-sm">
        <tr>
          <th>{gettext("Subject")}</th>
          <th>{gettext("Coefficient")}</th>
        </tr>
        <tr :for={subject <- @level_option.subjects}>
          <td>{subject.subject.name}</td>
          <td>{subject.coefficient}</td>
        </tr>
      </table>
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
         load: [:full_name, :level, :option, subjects: [:subject]],
         scope: socket.assigns.scope
       )
     )}
  end
end
