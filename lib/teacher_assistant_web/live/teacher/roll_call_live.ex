defmodule TeacherAssistantWeb.Teacher.RollCallLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_roll_call(socket, nil)}
  end

  @impl true
  def handle_event("create_session", %{"roll_call" => params}, socket) do
    with {:ok, classroom} <- Academics.get_personal_classroom(params["classroom_id"]),
         {:ok, session} <- Academics.create_attendance_session(classroom, params) do
      classroom
      |> Academics.list_learners()
      |> Enum.each(fn learner ->
        Academics.record_attendance(session, learner, %{status: :present})
      end)

      {:noreply,
       socket
       |> put_flash(:info, gettext("Roll call created"))
       |> assign_roll_call(session)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not create roll call"))}
    end
  end

  @impl true
  def handle_event("mark", %{"id" => learner_id, "status" => status}, socket) do
    session = socket.assigns.current_session
    learner = Enum.find(socket.assigns.learners, &(&1.id == learner_id))

    if session && learner && status_from_param(status) do
      Academics.record_attendance(session, learner, %{status: status_from_param(status)})
    end

    {:noreply, assign_roll_call(socket, session)}
  end

  defp assign_roll_call(socket, session) do
    workspace = socket.assigns.current_scope.current_workspace
    classrooms = Academics.list_personal_classrooms(workspace)

    selected_classroom =
      if session && session.personal_classroom_id do
        case Academics.get_personal_classroom(session.personal_classroom_id) do
          {:ok, classroom} -> classroom
          _ -> nil
        end
      end

    learners = if selected_classroom, do: Academics.list_learners(selected_classroom), else: []
    records = if session, do: Academics.list_attendance_records(session), else: []

    socket
    |> assign(:classrooms, classrooms)
    |> assign(:learners, learners)
    |> assign(:records, records)
    |> assign(:current_session, session)
    |> assign(:form, to_form(%{"date" => Date.utc_today()}, as: :roll_call))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="roll-call-workspace" class="space-y-6">
        <div>
          <p class="ta-section-label">{gettext("Daily work")}</p>
          <h1 class="text-3xl font-semibold">{gettext("Roll call")}</h1>
          <p class="mt-2 text-sm text-base-content/65">
            {gettext(
              "Create a roll-call session for one personal classroom and update learner statuses."
            )}
          </p>
        </div>

        <section class="ta-panel p-5">
          <.form
            for={@form}
            id="roll-call-form"
            phx-submit="create_session"
            class="grid gap-4 md:grid-cols-[1fr_1fr_auto] md:items-end"
          >
            <.input
              field={@form[:classroom_id]}
              type="select"
              label={gettext("Classroom")}
              options={Enum.map(@classrooms, &{"#{&1.class_label} · #{&1.subject}", &1.id})}
            />
            <.input field={@form[:date]} type="date" label={gettext("Date")} />
            <button id="create-roll-call" class="btn btn-primary">
              <.icon name="hero-clipboard-document-check" class="size-5" />
              {gettext("Start")}
            </button>
          </.form>
        </section>

        <section id="attendance-records" class="ta-panel p-5">
          <div class="flex items-center justify-between gap-4">
            <h2 class="font-semibold">{gettext("Attendance records")}</h2>
            <span :if={@current_session} class="badge badge-success">
              {@current_session.date}
            </span>
          </div>

          <div class="mt-4 overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Learner")}</th>
                  <th>{gettext("Status")}</th>
                  <th class="text-right">{gettext("Actions")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@current_session == nil}>
                  <td colspan="3" class="text-base-content/55">
                    {gettext("Start a roll call to see learners.")}
                  </td>
                </tr>
                <tr :for={learner <- @learners} id={"roll-call-learner-#{learner.id}"}>
                  <% record = Enum.find(@records, &(&1.learner_id == learner.id)) %>
                  <td class="font-medium">{learner.full_name}</td>
                  <td>
                    <span class="badge badge-sm">{record && record.status}</span>
                  </td>
                  <td class="text-right">
                    <button
                      :for={status <- [:present, :absent, :late, :excused]}
                      id={"mark-#{status}-#{learner.id}"}
                      class="btn btn-ghost btn-xs"
                      phx-click="mark"
                      phx-value-id={learner.id}
                      phx-value-status={status}
                    >
                      {status_label(status)}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp status_label(:present), do: gettext("Present")
  defp status_label(:absent), do: gettext("Absent")
  defp status_label(:late), do: gettext("Late")
  defp status_label(:excused), do: gettext("Excused")

  defp status_from_param("present"), do: :present
  defp status_from_param("absent"), do: :absent
  defp status_from_param("late"), do: :late
  defp status_from_param("excused"), do: :excused
  defp status_from_param(_status), do: nil
end
