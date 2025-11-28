defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <.link class="btn btn-sm btn-ghost" navigate={~p"/configurations/academic_years"}>
          <.icon name="hero-arrow-left" />
        </.link>
        {gettext("Academic Year")} {@academic_year.name}

        <:actions>
          <.button
            variant="primary"
            navigate={~p"/configurations/academic_years/#{@academic_year}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" />{gettext("Edit Academic Year")}
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@academic_year.name}</:item>
        <:item title="Description">{@academic_year.description}</:item>
      </.list>
      <div class="divider" />
      <h3 class="font-semibold text-2xl">{gettext("Terms")}</h3>
      <table class="table table-hover">
        <tr>
          <th>{gettext("Name")}</th>
          <th>{gettext("Period")}</th>
          <th></th>
        </tr>

        <tr :for={term <- @academic_year.terms}>
          <td>{term.name}</td>
          <td>{term.start_date} - {term.end_date}</td>
          <td>
            <.link navigate={~p"/configurations/academic_years/#{@academic_year}/terms/#{term}"}>
              {gettext("View")}
            </.link>
          </td>
        </tr>
      </table>

      <div class="divider" />
      <div class="flex justify-between">
        <h3 class="font-semibold text-xl">{gettext("Classrooms")}</h3>
        <.link
          class="btn btn-sm btn-soft btn-ghost"
          navigate={~p"/configurations/academic_years/#{@academic_year}/manage_classrooms"}
        >
          <.icon name="hero-pencil-square" />{gettext("Manage classrooms")}
        </.link>
      </div>
      <table class="table table-hover">
        <tr>
          <th>{gettext("Classroom")}</th>
          <th>{gettext("Actions")}</th>
        </tr>

        <tr :for={classroom <- @academic_year.classrooms}>
          <td>{classroom.level_option.full_name}</td>
          <td>
            <.link navigate={~p"/configurations/classrooms/#{classroom.id}/teachers_and_subjects"}>
              {gettext("Assign Teachers/Subjects")}
            </.link>
          </td>
        </tr>
      </table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Show Academic Year"))
     |> assign(
       :academic_year,
       Ash.get!(TeacherAssistant.Academics.AcademicYear, id,
         load: [classrooms: [level_option: [:full_name]], terms: [:sequences]],
         scope: socket.assigns.scope
       )
     )}
  end
end
