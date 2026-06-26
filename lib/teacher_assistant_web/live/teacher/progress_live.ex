defmodule TeacherAssistantWeb.Teacher.ProgressLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_progress(socket)}
  end

  @impl true
  def handle_event("create_plan", %{"lesson_plan" => params}, socket) do
    with {:ok, classroom} <- Academics.get_personal_classroom(params["classroom_id"]),
         {:ok, _entry} <- Academics.create_lesson_plan_entry(classroom, params) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Lesson planned"))
       |> assign_progress()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not plan lesson"))}
    end
  end

  @impl true
  def handle_event("create_log", %{"teaching_log" => params}, socket) do
    plan = Enum.find(socket.assigns.lesson_entries, &(&1.id == params["lesson_plan_entry_id"]))

    case plan && Academics.create_teaching_log_entry(plan, params) do
      {:ok, _log} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Teaching log added"))
         |> assign_progress()}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not add teaching log"))}
    end
  end

  defp assign_progress(socket) do
    workspace = socket.assigns.current_scope.current_workspace

    socket
    |> assign(:classrooms, Academics.list_personal_classrooms(workspace))
    |> assign(:lesson_entries, Academics.list_lesson_plan_entries(workspace))
    |> assign(
      :plan_form,
      to_form(%{"planned_on" => Date.utc_today(), "planned_hours" => "1.0"}, as: :lesson_plan)
    )
    |> assign(
      :log_form,
      to_form(%{"taught_on" => Date.utc_today(), "taught_hours" => "1.0"}, as: :teaching_log)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="lesson-progress-workspace" class="space-y-6">
        <div>
          <p class="ta-section-label">{gettext("Pedagogy")}</p>
          <h1 class="text-3xl font-semibold">{gettext("Lesson progress")}</h1>
          <p class="mt-2 text-sm text-base-content/65">
            {gettext("Plan lesson entries, then log what was actually taught.")}
          </p>
        </div>

        <div class="grid gap-5 lg:grid-cols-2">
          <section class="ta-panel p-5">
            <h2 class="font-semibold">{gettext("Plan a lesson")}</h2>
            <.form
              for={@plan_form}
              id="lesson-plan-form"
              phx-submit="create_plan"
              class="mt-4 space-y-4"
            >
              <.input
                field={@plan_form[:classroom_id]}
                type="select"
                label={gettext("Classroom")}
                options={Enum.map(@classrooms, &{"#{&1.class_label} · #{&1.subject}", &1.id})}
              />
              <.input field={@plan_form[:title]} label={gettext("Title")} />
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@plan_form[:planned_on]} type="date" label={gettext("Planned date")} />
                <.input
                  field={@plan_form[:planned_hours]}
                  type="number"
                  step="0.5"
                  label={gettext("Planned hours")}
                />
              </div>
              <.input field={@plan_form[:objectives]} type="textarea" label={gettext("Objectives")} />
              <button id="save-lesson-plan" class="btn btn-primary">
                <.icon name="hero-calendar-days" class="size-5" />
                {gettext("Save plan")}
              </button>
            </.form>
          </section>

          <section class="ta-panel p-5">
            <h2 class="font-semibold">{gettext("Log taught work")}</h2>
            <.form
              for={@log_form}
              id="teaching-log-form"
              phx-submit="create_log"
              class="mt-4 space-y-4"
            >
              <.input
                field={@log_form[:lesson_plan_entry_id]}
                type="select"
                label={gettext("Planned lesson")}
                options={Enum.map(@lesson_entries, &{&1.title, &1.id})}
              />
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@log_form[:taught_on]} type="date" label={gettext("Taught date")} />
                <.input
                  field={@log_form[:taught_hours]}
                  type="number"
                  step="0.5"
                  label={gettext("Taught hours")}
                />
              </div>
              <.input field={@log_form[:notes]} type="textarea" label={gettext("Notes")} />
              <button id="save-teaching-log" class="btn btn-outline">
                <.icon name="hero-check" class="size-5" />
                {gettext("Save taught log")}
              </button>
            </.form>
          </section>
        </div>

        <section id="lesson-plan-entries" class="ta-panel p-5">
          <h2 class="font-semibold">{gettext("Plan versus taught")}</h2>
          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Classroom")}</th>
                  <th>{gettext("Planned")}</th>
                  <th>{gettext("Lesson")}</th>
                  <th>{gettext("Taught logs")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@lesson_entries == []}>
                  <td colspan="4" class="text-base-content/55">
                    {gettext("No planned lessons yet.")}
                  </td>
                </tr>
                <tr :for={entry <- @lesson_entries} id={"progress-entry-#{entry.id}"}>
                  <td>{entry.personal_classroom.class_label} · {entry.personal_classroom.subject}</td>
                  <td>{entry.planned_on}</td>
                  <td class="font-medium">{entry.title}</td>
                  <td>{length(entry.teaching_logs)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
