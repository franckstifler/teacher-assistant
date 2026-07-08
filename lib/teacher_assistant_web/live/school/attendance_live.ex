defmodule TeacherAssistantWeb.School.AttendanceLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Permissions

  @valid_statuses %{"present" => :present, "absent" => :absent, "late" => :late}

  def mount(%{"id" => id, "period_id" => period_id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    date = parse_date(params["date"])

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         {:ok, period} <- fetch_period(period_id, scope.current_workspace),
         {:ok, slot_or_nil} <- resolve_slot(cg, date, period.id),
         true <- authorized?(scope, slot_or_nil) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         period: period,
         date: date,
         slot: slot_or_nil
       )
       |> load_roll()}
    else
      false -> {:ok, socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp parse_date(nil), do: Date.utc_today()

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  defp fetch_period(period_id, workspace) do
    workspace
    |> Timetables.list_periods()
    |> Enum.find(&(&1.id == period_id))
    |> case do
      nil -> {:error, :not_found}
      period -> {:ok, period}
    end
  end

  defp resolve_slot(cg, date, period_id) do
    case Attendance.slot_for(cg, date, period_id) do
      {:ok, slot} -> {:ok, slot}
      {:error, :no_slot} -> {:ok, nil}
    end
  end

  defp authorized?(scope, slot) do
    owns_slot?(scope, slot) or Permissions.conduct_manager?(scope)
  end

  defp owns_slot?(_scope, nil), do: false

  defp owns_slot?(scope, slot),
    do: slot.teaching_context.teacher_user_id == scope.current_user.id

  defp load_roll(socket) do
    roll = Attendance.period_roll(socket.assigns.cg, socket.assigns.period, socket.assigns.date)
    assign(socket, students: roll.students)
  end

  def handle_event("mark", %{"enrollment_id" => enrollment_id, "status" => status_str}, socket) do
    scope = socket.assigns.current_scope

    with true <- authorized?(scope, socket.assigns.slot),
         %{} = student <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)),
         status when not is_nil(status) <- Map.get(@valid_statuses, status_str) do
      teaching_context = socket.assigns.slot && socket.assigns.slot.teaching_context

      case Attendance.record_period(
             socket.assigns.cg,
             socket.assigns.period,
             teaching_context,
             socket.assigns.date,
             [{student.enrollment_id, status}],
             scope.current_user.id
           ) do
        {:ok, _count} -> {:noreply, load_roll(socket)}
        {:error, _reason} -> {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp status_label(:present), do: gettext("Présent")
  defp status_label(:absent), do: gettext("Absent")
  defp status_label(:late), do: gettext("Retard")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-attendance" class="space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Appel")} — #{@period.label}"}
        />

        <p class="text-sm text-base-content/70">{Date.to_string(@date)}</p>

        <div class="overflow-x-auto">
          <table id="attendance-roster" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Statut")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={student <- @students} id={"student-row-#{student.enrollment_id}"}>
                <td>{student.student_name}</td>
                <td>
                  <form phx-change="mark" id={"mark-#{student.enrollment_id}"}>
                    <input type="hidden" name="enrollment_id" value={student.enrollment_id} />
                    <select name="status" class="select select-bordered select-xs">
                      <option value="" selected={is_nil(student.status)}>{gettext("—")}</option>
                      <option value="present" selected={student.status == :present}>
                        {status_label(:present)}
                      </option>
                      <option value="absent" selected={student.status == :absent}>
                        {status_label(:absent)}
                      </option>
                      <option value="late" selected={student.status == :late}>
                        {status_label(:late)}
                      </option>
                    </select>
                  </form>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
