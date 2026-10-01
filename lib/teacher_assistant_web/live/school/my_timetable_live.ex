defmodule TeacherAssistantWeb.School.MyTimetableLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.DayOfWeek
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      calendar = Attendance.school_calendar(scope)

      {:ok,
       assign(socket,
         periods: Attendance.list_periods(scope),
         grid: Timetabling.teacher_timetable(scope, scope.current_user),
         calendar: calendar,
         days: calendar.lesson_days
       )}
    end
  end

  defp day_label(d), do: DayOfWeek.label(d)

  defp cell_slots(grid, day, period_id), do: Map.get(grid, {day, period_id}, [])

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-timetable" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Mon emploi du temps")} />

        <div class="flex justify-end">
          <a
            id="print-my-timetable"
            href={~p"/school/timetable/me/print"}
            target="_blank"
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer")}
          </a>
        </div>

        <%= if @grid == %{} do %>
          <.empty_state
            icon="hero-calendar-days"
            title={gettext("Aucun cours placé pour le moment")}
            message={gettext("Vous n'avez pas encore de créneau dans l'emploi du temps.")}
          />
        <% else %>
          <div class="overflow-x-auto">
            <table id="my-timetable-grid" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Période")}</th>
                  <th :for={day <- @days}>{day_label(day)}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={period <- @periods} id={"period-row-#{period.id}"}>
                  <%= if period.kind == :break do %>
                    <td colspan={length(@days) + 1} class="text-center italic text-base-content/60">
                      {period.label}
                    </td>
                  <% else %>
                    <td class="font-semibold">{period.label}</td>
                    <%= for day <- @days do %>
                      <%= if SchoolCalendar.open_cell?(@calendar, day, period) do %>
                        <td id={"cell-#{day}-#{period.id}"}>
                          <div
                            :for={slot <- cell_slots(@grid, day, period.id)}
                            class={length(cell_slots(@grid, day, period.id)) > 1 && "text-error"}
                          >
                            {slot.class_label} · {slot.subject}
                            <.link
                              navigate={
                                ~p"/school/classes/#{slot.class_group_id}/attendance/#{period.id}?date=#{Date.to_iso8601(Date.utc_today())}"
                              }
                              class="link link-primary block text-xs"
                            >
                              {gettext("Faire l'appel")}
                            </.link>
                          </div>
                        </td>
                      <% else %>
                        <td
                          id={"cell-#{day}-#{period.id}"}
                          class="closed-cell bg-base-200/60 text-center text-xs text-base-content/50"
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
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
