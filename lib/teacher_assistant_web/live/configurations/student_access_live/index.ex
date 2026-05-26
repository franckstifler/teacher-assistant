defmodule TeacherAssistantWeb.Configurations.StudentAccessLive.Index do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  alias TeacherAssistant.Academics.Classroom
  alias TeacherAssistant.Academics.ClassroomStudent

  @statuses ~w(allowed pending suspended blocked)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Student classroom access"))
     |> assign(:selected_classroom_id, nil)
     |> assign(:enrollments, [])
     |> load_classrooms()
     |> assign_filter_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>
          {gettext("Student classroom access")}
          <:subtitle>
            {gettext("Allow, suspend, or block enrolled students from attending class.")}
          </:subtitle>
        </.header>

        <section class="rounded-md border border-base-300 bg-base-100 p-5 shadow-sm">
          <.form
            for={@filter_form}
            id="student-access-filter"
            phx-change="filter"
            class="grid gap-3 md:grid-cols-[minmax(0,24rem)_auto]"
          >
            <.input
              field={@filter_form[:classroom_id]}
              type="select"
              label={gettext("Classroom")}
              options={classroom_options(@classrooms)}
            />
            <div class="flex items-end text-sm text-base-content/60">
              {gettext("Changes are audited with the current user and timestamp.")}
            </div>
          </.form>
        </section>

        <section
          id="student-access-table"
          class="overflow-x-auto rounded-md border border-base-300 bg-base-100"
        >
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Student")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Current status")}</th>
                <th>{gettext("Update access")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@selected_classroom_id == nil}>
                <td colspan="4" class="py-8 text-center text-sm text-base-content/60">
                  {gettext("Select a classroom to review access statuses.")}
                </td>
              </tr>
              <tr :if={@selected_classroom_id && @enrollments == []}>
                <td colspan="4" class="py-8 text-center text-sm text-base-content/60">
                  {gettext("No students are enrolled in this classroom.")}
                </td>
              </tr>
              <tr :for={enrollment <- @enrollments} id={"student-access-row-#{enrollment.id}"}>
                <td class="font-medium">{student_name(enrollment.student)}</td>
                <td>{enrollment.student.matricule}</td>
                <td>
                  <span
                    id={"access-status-#{enrollment.id}"}
                    class={status_badge(enrollment.access_status)}
                  >
                    {status_label(enrollment.access_status)}
                  </span>
                  <div :if={enrollment.access_note} class="mt-1 text-xs text-base-content/60">
                    {enrollment.access_note}
                  </div>
                </td>
                <td class="min-w-96">
                  <.form
                    for={to_form(%{}, as: :access)}
                    id={"student-access-form-#{enrollment.id}"}
                    phx-submit="set_access_status"
                    phx-value-id={enrollment.id}
                    class="grid gap-2 md:grid-cols-[10rem_minmax(0,1fr)_auto]"
                  >
                    <.input
                      field={to_form(%{}, as: :access)[:access_status]}
                      type="select"
                      label={gettext("Status")}
                      value={to_string(enrollment.access_status)}
                      options={status_options()}
                    />
                    <.input
                      field={to_form(%{}, as: :access)[:access_note]}
                      type="text"
                      label={gettext("Reason")}
                      value={enrollment.access_note || ""}
                    />
                    <div class="flex items-end">
                      <.button class="btn-sm" variant="primary">
                        <.icon name="hero-check" class="size-4" />
                        {gettext("Save")}
                      </.button>
                    </div>
                  </.form>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter", %{"filters" => %{"classroom_id" => classroom_id}}, socket) do
    {:noreply,
     socket
     |> assign(:selected_classroom_id, blank_to_nil(classroom_id))
     |> assign_filter_form()
     |> load_enrollments()}
  end

  def handle_event("set_access_status", %{"id" => id, "access" => params}, socket) do
    enrollment = Ash.get!(ClassroomStudent, id, scope: socket.assigns.scope)

    update_params =
      params
      |> Map.take(["access_status", "access_note"])
      |> Map.put("access_set_by_id", socket.assigns.current_user.id)

    result =
      enrollment
      |> Ash.Changeset.for_update(:set_access_status, update_params, scope: socket.assigns.scope)
      |> Ash.update()

    case result do
      {:ok, _enrollment} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Student access updated successfully"))
         |> load_enrollments()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  defp load_classrooms(socket) do
    classrooms =
      Classroom
      |> Ash.Query.load(level_option: [:level, :option])
      |> Ash.read!(scope: socket.assigns.scope)
      |> Enum.sort_by(&classroom_label/1)

    assign(socket, :classrooms, classrooms)
  end

  defp load_enrollments(%{assigns: %{selected_classroom_id: nil}} = socket) do
    assign(socket, :enrollments, [])
  end

  defp load_enrollments(socket) do
    enrollments =
      ClassroomStudent
      |> Ash.Query.filter(classroom_id == ^socket.assigns.selected_classroom_id)
      |> Ash.Query.load([:student, :access_set_by])
      |> Ash.read!(scope: socket.assigns.scope)
      |> Enum.sort_by(&student_name(&1.student))

    assign(socket, :enrollments, enrollments)
  end

  defp assign_filter_form(socket) do
    assign(
      socket,
      :filter_form,
      to_form(%{"classroom_id" => socket.assigns.selected_classroom_id || ""}, as: :filters)
    )
  end

  defp classroom_options(classrooms) do
    [{gettext("Select classroom"), ""} | Enum.map(classrooms, &{classroom_label(&1), &1.id})]
  end

  defp classroom_label(%{level_option: %{level: level, option: option}}) do
    "#{level.name} #{option.name}"
  end

  defp classroom_label(_classroom), do: gettext("Classroom")

  defp student_name(student), do: "#{student.first_name} #{student.last_name}"

  defp status_options, do: Enum.map(@statuses, &{status_label(&1), &1})

  defp status_label(status) do
    status
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_badge(:allowed), do: "badge badge-success badge-sm"
  defp status_badge(:pending), do: "badge badge-warning badge-sm"
  defp status_badge(:suspended), do: "badge badge-error badge-sm"
  defp status_badge(:blocked), do: "badge badge-neutral badge-sm"
  defp status_badge(status), do: status_badge(String.to_existing_atom(status))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
