defmodule TeacherAssistantWeb.Teacher.AttendanceLive.Entry do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <.icon name="hero-clipboard-document-check" class="w-8 h-8 inline" />
        {gettext("Attendance Tracking")}
        <:subtitle>
          {gettext("Track student attendance for your classes")}
        </:subtitle>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-4 gap-6 mt-6">
        <%!-- Filters Card --%>
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">
              <.icon name="hero-funnel" class="w-5 h-5" />
              {gettext("Filters")}
            </h2>

            <.form for={@filter_form} id="filter-form">
              <div class="form-control w-full">
                <label class="label">
                  <span class="label-text font-semibold">{gettext("Date")}</span>
                </label>
                <input
                  type="date"
                  name="date"
                  value={@selected_date}
                  phx-change="date_changed"
                  class="input input-bordered w-full"
                />
              </div>

              <%= if @selected_date do %>
                <div class="form-control w-full mt-4">
                  <label class="label">
                    <span class="label-text font-semibold">{gettext("Class")}</span>
                  </label>
                  <select
                    name="classroom_id"
                    class="select select-bordered w-full"
                    phx-change="classroom_changed"
                  >
                    <option value="">{gettext("Select class...")}</option>
                    <%= for classroom <- @classrooms do %>
                      <option value={classroom.id} selected={classroom.id == @selected_classroom_id}>
                        {classroom.level_option_name}
                      </option>
                    <% end %>
                  </select>
                </div>
              <% end %>
            </.form>

            <%= if @selected_classroom_id do %>
              <div class="divider"></div>
              <div class="flex gap-2">
                <button phx-click="mark_all_present" class="btn btn-success btn-sm flex-1">
                  <.icon name="hero-check-circle" class="w-4 h-4" />
                  {gettext("All Present")}
                </button>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Attendance Entry Table --%>
        <div class="lg:col-span-3">
          <%= if @selected_classroom_id do %>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <div class="flex justify-between items-center mb-4">
                  <h2 class="card-title">
                    <.icon name="hero-users" class="w-5 h-5" />
                    {gettext("Student Attendance")} - {format_date(@selected_date)}
                  </h2>
                  <button phx-click="save_all" class="btn btn-primary">
                    <.icon name="hero-check" class="w-5 h-5" />
                    {gettext("Save All")}
                  </button>
                </div>

                <div class="overflow-x-auto">
                  <table class="table table-zebra">
                    <thead>
                      <tr>
                        <th class="w-1/12">{gettext("#")}</th>
                        <th class="w-5/12">{gettext("Student Name")}</th>
                        <th class="w-3/12 text-center">{gettext("Status")}</th>
                        <th class="w-3/12">{gettext("Comment")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {student, index} <- Enum.with_index(@students, 1) do %>
                        <% attendance = find_attendance(@attendances, student.id) %>
                        <% status = (attendance && attendance.status) || :present %>
                        <tr class="hover">
                          <td class="font-semibold">{index}</td>
                          <td>
                            <div class="flex items-center gap-2">
                              <.icon name="hero-user-circle" class="w-5 h-5 text-primary" />
                              <span class="font-medium">{student.full_name}</span>
                            </div>
                          </td>
                          <td>
                            <div class="flex justify-center gap-2">
                              <button
                                phx-click="set_status"
                                phx-value-student-id={student.id}
                                phx-value-attendance-id={attendance && attendance.id}
                                phx-value-status="present"
                                class={[
                                  "btn btn-sm",
                                  if(status == :present, do: "btn-success", else: "btn-ghost")
                                ]}
                              >
                                <.icon name="hero-check-circle" class="w-4 h-4" />
                                {gettext("Present")}
                              </button>
                              <button
                                phx-click="set_status"
                                phx-value-student-id={student.id}
                                phx-value-attendance-id={attendance && attendance.id}
                                phx-value-status="absent"
                                class={[
                                  "btn btn-sm",
                                  if(status == :absent, do: "btn-error", else: "btn-ghost")
                                ]}
                              >
                                <.icon name="hero-x-circle" class="w-4 h-4" />
                                {gettext("Absent")}
                              </button>
                              <button
                                phx-click="set_status"
                                phx-value-student-id={student.id}
                                phx-value-attendance-id={attendance && attendance.id}
                                phx-value-status="excused"
                                class={[
                                  "btn btn-sm",
                                  if(status == :excused, do: "btn-warning", else: "btn-ghost")
                                ]}
                              >
                                <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                                {gettext("Excused")}
                              </button>
                            </div>
                          </td>
                          <td>
                            <input
                              type="text"
                              value={attendance && attendance.comment}
                              phx-blur="update_comment"
                              phx-value-student-id={student.id}
                              phx-value-attendance-id={attendance && attendance.id}
                              name="comment"
                              class="input input-bordered input-sm w-full"
                              placeholder={gettext("Optional comment...")}
                            />
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>

                <%= if Enum.empty?(@students) do %>
                  <div class="alert alert-warning">
                    <.icon name="hero-exclamation-triangle" />
                    <span>{gettext("No students enrolled in this class")}</span>
                  </div>
                <% end %>

                <div class="stats shadow mt-4">
                  <div class="stat">
                    <div class="stat-figure text-primary">
                      <.icon name="hero-users" class="w-8 h-8" />
                    </div>
                    <div class="stat-title">{gettext("Total Students")}</div>
                    <div class="stat-value text-primary">{length(@students)}</div>
                  </div>
                  <div class="stat">
                    <div class="stat-figure text-success">
                      <.icon name="hero-check-circle" class="w-8 h-8" />
                    </div>
                    <div class="stat-title">{gettext("Present")}</div>
                    <div class="stat-value text-success">
                      {count_by_status(@attendances, :present)}
                    </div>
                  </div>
                  <div class="stat">
                    <div class="stat-figure text-error">
                      <.icon name="hero-x-circle" class="w-8 h-8" />
                    </div>
                    <div class="stat-title">{gettext("Absent")}</div>
                    <div class="stat-value text-error">{count_by_status(@attendances, :absent)}</div>
                  </div>
                  <div class="stat">
                    <div class="stat-figure text-warning">
                      <.icon name="hero-exclamation-circle" class="w-8 h-8" />
                    </div>
                    <div class="stat-title">{gettext("Excused")}</div>
                    <div class="stat-value text-warning">
                      {count_by_status(@attendances, :excused)}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body items-center text-center">
                <.icon name="hero-calendar" class="w-16 h-16 text-base-content/20" />
                <h3 class="text-xl font-semibold text-base-content/50">
                  {gettext("Select date and class to begin")}
                </h3>
                <p class="text-base-content/40">
                  {gettext("Choose a date and class to track attendance")}
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today() |> Date.to_string()

    {:ok,
     socket
     |> assign(:selected_date, today)
     |> assign(:classrooms, [])
     |> assign(:students, [])
     |> assign(:attendances, [])
     |> assign(:selected_classroom_id, nil)
     |> assign(:filter_form, to_form(%{}))
     |> load_classrooms()}
  end

  @impl true
  def handle_event("date_changed", %{"date" => date}, socket) do
    {:noreply,
     socket
     |> assign(:selected_date, date)
     |> assign(:students, [])
     |> assign(:attendances, [])
     |> assign(:selected_classroom_id, nil)
     |> load_classrooms()}
  end

  def handle_event("classroom_changed", %{"classroom_id" => classroom_id}, socket) do
    {students, attendances} =
      if classroom_id != "" do
        students =
          case TeacherAssistant.Academics.list_students_by_classroom(classroom_id,
                 load: [:full_name],
                 scope: socket.assigns.scope
               ) do
            {:ok, students} -> students
            _ -> []
          end

        date = Date.from_iso8601!(socket.assigns.selected_date)

        attendances =
          TeacherAssistant.Academics.Attendance
          |> Ash.Query.filter(classroom_id == ^classroom_id and date == ^date)
          |> Ash.read!(scope: socket.assigns.scope)

        {students, attendances}
      else
        {[], []}
      end

    {:noreply,
     socket
     |> assign(:selected_classroom_id, if(classroom_id == "", do: nil, else: classroom_id))
     |> assign(:students, students)
     |> assign(:attendances, attendances)}
  end

  def handle_event(
        "set_status",
        %{"student-id" => student_id, "attendance-id" => attendance_id, "status" => status},
        socket
      ) do
    date = Date.from_iso8601!(socket.assigns.selected_date)

    with {:ok, status_atom} <- parse_attendance_status(status),
         {:ok, _attendance} <-
           save_attendance(socket, student_id, attendance_id, date, %{status: status_atom}) do
      {:noreply, assign(socket, :attendances, read_attendances(socket, date))}
    else
      _error ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save attendance"))}
    end
  end

  def handle_event(
        "update_comment",
        %{"student-id" => student_id, "attendance-id" => attendance_id, "value" => comment},
        socket
      ) do
    date = Date.from_iso8601!(socket.assigns.selected_date)

    case save_attendance(socket, student_id, attendance_id, date, %{comment: comment}) do
      {:ok, _attendance} ->
        {:noreply, assign(socket, :attendances, read_attendances(socket, date))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to save comment"))}
    end
  end

  def handle_event("mark_all_present", _params, socket) do
    date = Date.from_iso8601!(socket.assigns.selected_date)

    Enum.each(socket.assigns.students, fn student ->
      save_attendance(socket, student.id, nil, date, %{status: :present})
    end)

    {:noreply,
     socket
     |> assign(:attendances, read_attendances(socket, date))
     |> put_flash(:info, gettext("All students marked as present"))}
  end

  def handle_event("save_all", _params, socket) do
    {:noreply, put_flash(socket, :info, gettext("All attendance records saved successfully"))}
  end

  defp load_classrooms(socket) do
    user_id = socket.assigns.current_user.id

    assignments =
      TeacherAssistant.Academics.TeachingAssignment
      |> Ash.Query.filter(teacher_id == ^user_id)
      |> Ash.Query.load(:classroom)
      |> Ash.read!(scope: socket.assigns.scope)

    classrooms =
      assignments
      |> Enum.map(& &1.classroom)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(fn classroom ->
        level_option =
          Ash.get!(TeacherAssistant.Academics.LevelOption, classroom.level_option_id,
            load: [:level, :option],
            scope: socket.assigns.scope
          )

        Map.put(
          classroom,
          :level_option_name,
          "#{level_option.level.name} #{level_option.option.name}"
        )
      end)

    assign(socket, :classrooms, classrooms)
  end

  defp find_attendance(attendances, student_id) do
    Enum.find(attendances, &(&1.student_id == student_id))
  end

  defp save_attendance(socket, student_id, attendance_id, date, params) do
    params =
      params
      |> Map.put_new(:student_id, student_id)
      |> Map.put_new(:classroom_id, socket.assigns.selected_classroom_id)
      |> Map.put_new(:date, date)
      |> Map.put_new(:status, :present)

    case attendance_id do
      attendance_id when is_binary(attendance_id) and attendance_id != "" ->
        case Enum.find(socket.assigns.attendances, &(&1.id == attendance_id)) do
          nil ->
            Ash.create(TeacherAssistant.Academics.Attendance, :create,
              params: params,
              scope: socket.assigns.scope
            )

          attendance ->
            Ash.update(attendance, :update, params: params, scope: socket.assigns.scope)
        end

      _ ->
        Ash.create(TeacherAssistant.Academics.Attendance, :create,
          params: params,
          scope: socket.assigns.scope
        )
    end
  end

  defp read_attendances(socket, date) do
    classroom_id = socket.assigns.selected_classroom_id

    TeacherAssistant.Academics.Attendance
    |> Ash.Query.filter(classroom_id == ^classroom_id and date == ^date)
    |> Ash.read!(scope: socket.assigns.scope)
  end

  defp parse_attendance_status("present"), do: {:ok, :present}
  defp parse_attendance_status("absent"), do: {:ok, :absent}
  defp parse_attendance_status("excused"), do: {:ok, :excused}
  defp parse_attendance_status(_status), do: :error

  defp count_by_status(attendances, status) do
    Enum.count(attendances, &(&1.status == status))
  end

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end
end
