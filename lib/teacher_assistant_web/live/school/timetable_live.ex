defmodule TeacherAssistantWeb.School.TimetableLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.DayOfWeek
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling

  # The class's week, read-only. Spec J4: lessons are placed in the school-wide
  # editor, which editors open from here (« Modifier »).
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :timetable) do
      calendar = Attendance.school_calendar(scope)

      {:ok,
       socket
       |> assign(
         page_title: ClassShell.page_title(cg, :timetable),
         cg: cg,
         can_edit_timetable?: Timetabling.can_edit_timetable?(scope),
         periods: Attendance.list_periods(scope),
         assignments: Curriculum.list_assignments_for_class(scope, cg),
         calendar: calendar,
         days: calendar.lesson_days
       )
       |> ClassShell.assign_shell()
       |> load_timetable()}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp load_timetable(socket) do
    timetable = Timetabling.class_timetable(socket.assigns.current_scope, socket.assigns.cg)
    assign(socket, slots: timetable.slots, tally: timetable.tally)
  end

  defp day_label(d), do: DayOfWeek.label(d)

  defp time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")

  defp teacher_of(assignments, teaching_context_id) do
    case Enum.find(assignments, &(&1.id == teaching_context_id)) do
      %{teacher: %{} = teacher} -> User.display_name(teacher)
      _ -> nil
    end
  end

  defp status_badge_class(:under), do: "badge-warning"
  defp status_badge_class(:exact), do: "badge-success"
  defp status_badge_class(:over), do: "badge-error"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:timetable}>
        <:actions>
          <.link
            :if={@can_edit_timetable?}
            id="edit-class-timetable"
            navigate={~p"/school/timetable?class=#{@cg.id}"}
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-pencil-square" class="size-4" />
            {gettext("Modifier")}
          </.link>
          <a
            id="print-class-timetable"
            href={~p"/school/classes/#{@cg.id}/timetable/print"}
            target="_blank"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer")}
          </a>
        </:actions>

        <%!-- Phones: the week read day by day. --%>
        <div id="timetable-days" class="space-y-4 sm:hidden">
          <section :for={day <- @days} class="space-y-2">
            <h2 class="text-sm font-semibold">{day_label(day)}</h2>
            <div class="ta-section">
              <%= for period <- @periods, period.kind != :break, slot = @slots[{day, period.id}] do %>
                <.list_row
                  title={slot.subject}
                  meta={
                    Enum.join(
                      [
                        "#{period.label} · #{time(period.start_time)}–#{time(period.end_time)}",
                        teacher_of(@assignments, slot.teaching_context_id)
                      ]
                      |> Enum.reject(&is_nil/1),
                      " · "
                    )
                  }
                />
              <% end %>
              <p
                :if={Enum.all?(@periods, &is_nil(@slots[{day, &1.id}]))}
                class="px-4 py-3 text-sm text-base-content/70"
              >
                {gettext("Pas de cours")}
              </p>
            </div>
          </section>
        </div>

        <div class="hidden overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100 sm:block">
          <table id="timetable-grid" class="table">
            <thead>
              <tr>
                <th>{gettext("Période")}</th>
                <th :for={day <- @days}>{day_label(day)}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={period <- @periods} id={"period-row-#{period.id}"}>
                <%= if period.kind == :break do %>
                  <td colspan={length(@days) + 1} class="text-center italic text-base-content/70">
                    {period.label}
                  </td>
                <% else %>
                  <td class="font-semibold">{period.label}</td>
                  <%= for day <- @days do %>
                    <%= if SchoolCalendar.open_cell?(@calendar, day, period) do %>
                      <td id={"cell-#{day}-#{period.id}"}>
                        <% slot = @slots[{day, period.id}] %>
                        <span :if={slot}>{slot.subject}</span>
                      </td>
                    <% else %>
                      <td
                        id={"cell-#{day}-#{period.id}"}
                        class="closed-cell bg-base-200/60 text-center text-xs text-base-content/70"
                      >
                        {gettext("Libre")}
                      </td>
                    <% end %>
                  <% end %>
                <% end %>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="ta-section space-y-2 p-4">
          <h2 class="text-sm font-semibold">{gettext("Heures par matière")}</h2>
          <ul id="timetable-tally" class="space-y-1 text-sm">
            <li :for={row <- @tally} id={"tally-#{row.teaching_context_id}"}>
              <span class={["badge badge-sm", status_badge_class(row.status)]}>
                {row.subject} {row.placed}/{row.required}
              </span>
            </li>
          </ul>
        </div>
      </.class_shell>
    </Layouts.app>
    """
  end
end
