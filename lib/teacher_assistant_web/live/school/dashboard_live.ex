defmodule TeacherAssistantWeb.School.DashboardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Permissions

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type == :school do
      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:admin?, Permissions.admin?(scope))
       |> load_stats()}
    else
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-dashboard" class="space-y-4">
        <.page_header eyebrow={gettext("École")} title={@current_scope.current_workspace.name} />

        <%= cond do %>
          <% @year == nil -> %>
            <.setup_gate
              icon="hero-calendar"
              eyebrow={gettext("Get started")}
              title={gettext("No active academic year")}
              message={
                if @admin?,
                  do: gettext("Set up an academic year before managing your school."),
                  else: gettext("L'année scolaire n'a pas encore été créée.")
              }
            >
              <:action>
                <.link :if={@admin?} navigate={~p"/school/settings"} class="btn btn-primary">
                  {gettext("Go to settings")}
                </.link>
              </:action>
            </.setup_gate>
          <% @classes == [] -> %>
            <.setup_gate
              icon="hero-rectangle-group"
              eyebrow={gettext("Get started")}
              title={gettext("No classes yet")}
              message={gettext("Create your first class to start enrolling students.")}
            >
              <:action>
                <.link navigate={~p"/school/classes"} class="btn btn-primary">
                  {gettext("Go to classes")}
                </.link>
              </:action>
            </.setup_gate>
          <% true -> %>
            <div class="grid gap-4 sm:grid-cols-3">
              <.stat label={gettext("Classes")} value={Integer.to_string(@classes_count)} />
              <.stat label={gettext("Students")} value={Integer.to_string(@students_count)} />
              <.stat label={gettext("Teachers")} value={Integer.to_string(@teachers_count)} />
            </div>
        <% end %>

        <div :if={@my_classes != []} id="my-classes" class="ta-leaf space-y-2">
          <h2 class="text-sm font-semibold">{gettext("Mes classes")}</h2>
          <ul class="space-y-1">
            <li :for={c <- @my_classes}>
              <.link navigate={~p"/school/classes/#{c.id}"} class="link">
                {c.label} — {c.level}
              </.link>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_stats(socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    classes =
      if year, do: Academics.list_class_groups(scope.current_workspace, year), else: []

    students_count =
      classes
      |> Enum.map(&length(Academics.list_roster(&1)))
      |> Enum.sum()

    teachers_count =
      classes
      |> Enum.flat_map(&Assignments.list_for_class(&1))
      |> Enum.map(& &1.teacher_user_id)
      |> Enum.uniq()
      |> length()

    my_classes =
      if year,
        do: Academics.list_form_master_classes(scope.current_workspace, scope.current_user, year),
        else: []

    socket
    |> assign(:year, year)
    |> assign(:classes, classes)
    |> assign(:classes_count, length(classes))
    |> assign(:students_count, students_count)
    |> assign(:teachers_count, teachers_count)
    |> assign(:my_classes, my_classes)
  end
end
