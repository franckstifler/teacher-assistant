defmodule TeacherAssistantWeb.School.MyTimetableLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{DayOfWeek, Reference}
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      calendar = Attendance.school_calendar(scope)
      today = Reference.today()

      {:ok,
       assign(socket,
         periods: Attendance.list_periods(scope),
         grid: Timetabling.teacher_timetable(scope, scope.current_user),
         service: Timetabling.teacher_service(scope, scope.current_user),
         calendar: calendar,
         days: calendar.lesson_days,
         today: today,
         today_day: weekday(today)
       )}
    end
  end

  defp day_label(d), do: DayOfWeek.label(d)

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]
  defp weekday(date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  # Phone list: the school days starting from today.
  defp days_from_today(days, today_day) do
    {before, from} = Enum.split_while(days, &(&1 != today_day))
    from ++ before
  end

  defp time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")

  defp roll_call_path(slot, period, today),
    do:
      ~p"/school/classes/#{slot.class_group_id}/attendance/#{period.id}?date=#{Date.to_iso8601(today)}"

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
          <div id="my-timetable-days" class="space-y-4 sm:hidden">
            <section :for={day <- days_from_today(@days, @today_day)} class="space-y-2">
              <h2 class="text-sm font-semibold">
                {day_label(day)}
                <span :if={day == @today_day} class="text-primary">· {gettext("aujourd'hui")}</span>
              </h2>
              <div class="ta-section">
                <%= for period <- @periods, period.kind != :break, slot <- cell_slots(@grid, day, period.id) do %>
                  <.list_row
                    navigate={day == @today_day && roll_call_path(slot, period, @today)}
                    title={"#{slot.class_label} · #{slot.subject}"}
                    meta={
                      Enum.join(
                        [
                          period.label,
                          "#{time(period.start_time)}–#{time(period.end_time)}",
                          slot.room_name
                        ]
                        |> Enum.reject(&is_nil/1),
                        " · "
                      )
                    }
                  />
                <% end %>
                <p
                  :if={Enum.all?(@periods, &(cell_slots(@grid, day, &1.id) == []))}
                  class="px-4 py-3 text-sm text-base-content/70"
                >
                  {gettext("Pas de cours")}
                </p>
              </div>
            </section>
          </div>

          <div class="ta-panel hidden overflow-x-auto !p-2 sm:block">
            <table id="my-timetable-grid" class="table table-sm min-w-[700px] table-fixed">
              <thead>
                <tr>
                  <th class="w-24">{gettext("Période")}</th>
                  <th
                    :for={day <- @days}
                    class={day == @today_day && "text-primary"}
                    aria-current={day == @today_day && "date"}
                  >
                    {day_label(day)}
                    <span :if={day == @today_day} class="font-normal normal-case">
                      · {gettext("aujourd'hui")}
                    </span>
                  </th>
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
                            <p :if={slot.room_name} class="text-xs text-base-content/70">
                              {slot.room_name}
                            </p>
                            <.link
                              :if={day == @today_day}
                              navigate={roll_call_path(slot, period, @today)}
                              class="link link-primary block text-xs"
                            >
                              {gettext("Faire l'appel")}
                            </.link>
                          </div>
                        </td>
                      <% else %>
                        <td
                          id={"cell-#{day}-#{period.id}"}
                          class="closed-cell bg-base-300/50 text-center text-xs text-base-content/70"
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
