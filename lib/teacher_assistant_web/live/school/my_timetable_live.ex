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
         service: Timetabling.teacher_service(scope, scope.current_user),
         calendar: calendar,
         days: calendar.lesson_days
       )}
    end
  end

  defp day_label(d), do: DayOfWeek.label(d)

  defp cell_slots(grid, day, period_id), do: Map.get(grid, {day, period_id}, [])

  # « 14 h par semaine · service attendu : 18 h » (service part only when one is set).
  defp hours_line(%{load: load, service: nil}), do: gettext("%{n} h par semaine", n: load)

  defp hours_line(%{load: load, service: service}),
    do:
      gettext("%{n} h par semaine", n: load) <>
        " · " <> gettext("service attendu : %{m} h", m: service)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-timetable" class="space-y-6">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p class="ta-eyebrow">{gettext("Semaine type")}</p>
            <h1 class="mt-1.5 text-2xl font-semibold leading-[1.1] sm:text-[2rem]">
              {gettext("Mon emploi du temps")}
            </h1>
            <p id="my-timetable-hours" class="ta-num mt-2 text-[0.95rem] text-base-content/80">
              {hours_line(@service)}
            </p>
          </div>
          <a
            id="print-my-timetable"
            href={~p"/school/timetable/me/print"}
            target="_blank"
            class="btn btn-outline btn-sm gap-2"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer")}
          </a>
        </header>

        <%= if @grid == %{} do %>
          <.empty_state
            icon="hero-calendar-days"
            title={gettext("Aucun cours placé pour le moment")}
            message={gettext("Vous n'avez pas encore de créneau dans l'emploi du temps.")}
          />
        <% else %>
          <div class="ta-leaf overflow-x-auto p-2">
            <table id="my-timetable-grid" class="table table-sm min-w-[700px] table-fixed">
              <thead>
                <tr>
                  <th class="w-24">{gettext("Période")}</th>
                  <th :for={day <- @days}>{day_label(day)}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={period <- @periods} id={"period-row-#{period.id}"}>
                  <%= if period.kind == :break do %>
                    <td
                      colspan={length(@days) + 1}
                      class="bg-base-200/60 py-1 text-center text-xs italic text-base-content/70"
                    >
                      {period.label}
                    </td>
                  <% else %>
                    <td class="ta-num text-xs font-semibold text-base-content/70">
                      {period.label}
                    </td>
                    <%= for day <- @days do %>
                      <%= if SchoolCalendar.open_cell?(@calendar, day, period) do %>
                        <td id={"cell-#{day}-#{period.id}"} class="p-1 align-top">
                          <div
                            :for={slot <- cell_slots(@grid, day, period.id)}
                            class={[
                              "mb-1 rounded px-2 py-1.5 last:mb-0",
                              if(length(cell_slots(@grid, day, period.id)) > 1,
                                do: "bg-error/15 text-error",
                                else: "bg-primary/15"
                              )
                            ]}
                          >
                            <p class="font-semibold leading-tight">{slot.class_label}</p>
                            <p class="text-xs text-base-content/70">{slot.subject}</p>
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
                          class="closed-cell bg-base-300/50 text-center text-xs text-base-content/50"
                        >
                          {gettext("Fermé")}
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
