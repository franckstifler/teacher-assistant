defmodule TeacherAssistantWeb.School.AttendanceLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Accounts.Permissions

  @valid_statuses %{"present" => :present, "absent" => :absent, "late" => :late}
  @statuses [:present, :absent, :late]

  def mount(%{"id" => id, "period_id" => period_id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    date = parse_date(params["date"])

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         {:ok, period} <- fetch_period(period_id, scope.current_workspace),
         {:ok, slot_or_nil} <- resolve_slot(cg, date, period.id),
         true <- authorized?(scope, slot_or_nil) do
      {:ok,
       socket
       |> assign(cg: cg, period: period, date: date, slot: slot_or_nil, statuses: @statuses)
       |> load_roll()}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
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
    |> TeacherAssistant.Academics.Timetables.list_periods()
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

  # Roll starts with every student PRESENT (the cahier d'appel default); the
  # teacher only taps the absent/late few. `taken?` records whether the roll has
  # already been saved, so "all present" is distinguishable from "not yet done".
  defp load_roll(socket) do
    %{students: roster} =
      Attendance.period_roll(socket.assigns.cg, socket.assigns.period, socket.assigns.date)

    taken? = Enum.any?(roster, &(&1.status != nil))
    roll = Map.new(roster, fn s -> {s.enrollment_id, s.status || :present} end)

    students =
      Enum.map(roster, &%{enrollment_id: &1.enrollment_id, student_name: &1.student_name})

    assign(socket, students: students, roll: roll, taken?: taken?)
  end

  def handle_event("set", %{"enrollment_id" => enrollment_id, "status" => status_str}, socket) do
    with %{} <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)),
         status when not is_nil(status) <- Map.get(@valid_statuses, status_str) do
      {:noreply, assign(socket, :roll, Map.put(socket.assigns.roll, enrollment_id, status))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("record", _params, socket) do
    scope = socket.assigns.current_scope

    if authorized?(scope, socket.assigns.slot) do
      teaching_context = socket.assigns.slot && socket.assigns.slot.teaching_context

      marks =
        Enum.map(socket.assigns.students, fn s ->
          {s.enrollment_id, Map.fetch!(socket.assigns.roll, s.enrollment_id)}
        end)

      case Attendance.record_period(
             socket.assigns.cg,
             socket.assigns.period,
             teaching_context,
             socket.assigns.date,
             marks,
             scope.current_user.id
           ) do
        {:ok, _count} ->
          {:noreply, socket |> put_flash(:info, gettext("Appel enregistré")) |> load_roll()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Impossible d'enregistrer l'appel"))}
      end
    else
      {:noreply, socket}
    end
  end

  defp status_label(:present), do: gettext("Présent")
  defp status_label(:absent), do: gettext("Absent")
  defp status_label(:late), do: gettext("Retard")

  defp status_short(:present), do: "P"
  defp status_short(:absent), do: "A"
  defp status_short(:late), do: "R"

  defp active_class(:present), do: "btn-success"
  defp active_class(:absent), do: "btn-error"
  defp active_class(:late), do: "btn-warning"

  defp count(roll, status), do: Enum.count(roll, fn {_id, s} -> s == status end)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-attendance" class="mx-auto max-w-2xl space-y-4">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Appel")} — #{@period.label}"}
        />

        <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
          <p class="text-base-content/70">{Date.to_string(@date)}</p>
          <p id="roll-status" class={["badge", (@taken? && "badge-success") || "badge-ghost"]}>
            {if @taken?, do: gettext("Appel enregistré"), else: gettext("Appel non fait")}
          </p>
        </div>

        <p id="roll-summary" class="ta-num text-sm text-base-content/70">
          {gettext("%{p} présents · %{a} absents · %{r} retards",
            p: count(@roll, :present),
            a: count(@roll, :absent),
            r: count(@roll, :late)
          )}
        </p>

        <ul class="space-y-1">
          <li
            :for={student <- @students}
            id={"student-row-#{student.enrollment_id}"}
            class="ta-leaf flex items-center justify-between gap-3"
          >
            <span class="min-w-0 flex-1 truncate">{student.student_name}</span>
            <div class="join" role="group" aria-label={student.student_name}>
              <button
                :for={status <- @statuses}
                type="button"
                id={"att-#{student.enrollment_id}-#{status}"}
                phx-click="set"
                phx-value-enrollment_id={student.enrollment_id}
                phx-value-status={status}
                aria-pressed={to_string(Map.get(@roll, student.enrollment_id) == status)}
                title={status_label(status)}
                class={[
                  "join-item btn btn-sm",
                  (Map.get(@roll, student.enrollment_id) == status && active_class(status)) ||
                    "btn-ghost"
                ]}
              >
                {status_short(status)}
              </button>
            </div>
          </li>
        </ul>

        <.button id="record-roll" phx-click="record" class="btn btn-primary w-full">
          {if @taken?, do: gettext("Mettre à jour l'appel"), else: gettext("Enregistrer l'appel")}
        </.button>
      </section>
    </Layouts.app>
    """
  end
end
