defmodule TeacherAssistantWeb.Configurations.AcademicYearLive.Show do
  use TeacherAssistantWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
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
      <h3 class="font-semibold text-2xl mb-4">
        <.icon name="hero-calendar-days" class="w-6 h-6 inline" />
        {gettext("Terms")}
      </h3>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={term <- @academic_year.terms}
          class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-bookmark" class="w-5 h-5 text-primary" />
              {term.name}
            </h2>
            <div class="text-sm text-base-content/70">
              <div class="flex items-center gap-2 mb-2">
                <.icon name="hero-calendar" class="w-4 h-4" />
                <span>{term.start_date} - {term.end_date}</span>
              </div>
              <div class="mt-3">
                <p class="font-semibold mb-1">{gettext("Sequences")}:</p>
                <ul class="list-disc list-inside space-y-1">
                  <li :for={sequence <- term.sequences} class="text-xs">
                    {sequence.name}
                  </li>
                </ul>
              </div>
            </div>
            <div class="card-actions justify-end mt-4">
              <.link
                navigate={~p"/configurations/academic_years/#{@academic_year}/terms/#{term}"}
                class="btn btn-primary btn-sm"
              >
                <.icon name="hero-eye" class="w-4 h-4" />
                {gettext("View Details")}
              </.link>
            </div>
          </div>
        </div>
      </div>

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
      <div class="overflow-x-auto">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th class="w-1/3">{gettext("Classroom")}</th>
              <th class="w-2/3">{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={classroom <- @academic_year.classrooms} class="hover">
              <td>
                <div class="flex items-center gap-2">
                  <.icon name="hero-academic-cap" class="w-5 h-5 text-primary" />
                  <span class="font-semibold">{classroom.level_option.full_name}</span>
                </div>
              </td>
              <td>
                <div class="flex gap-2 flex-wrap">
                  <.link
                    class="btn btn-sm btn-primary"
                    navigate={~p"/configurations/classrooms/#{classroom}/teachers_and_subjects"}
                  >
                    <.icon name="hero-user-plus" class="w-4 h-4" />
                    {gettext("Assign Teachers")}
                  </.link>
                  <.link
                    class="btn btn-sm btn-secondary"
                    navigate={
                      ~p"/configurations/academic_years/#{@academic_year}/classrooms/#{classroom}/students"
                    }
                  >
                    <.icon name="hero-user-group" class="w-4 h-4" />
                    {gettext("Manage Students")}
                  </.link>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
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
