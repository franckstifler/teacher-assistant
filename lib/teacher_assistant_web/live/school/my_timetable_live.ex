defmodule TeacherAssistantWeb.School.MyTimetableLive do
  @moduledoc """
  Mon emploi du temps (UX refonte 2026-11-03). On phones a strip of the school
  days, each with its number of lessons, and one day at a time as cards (times,
  « Cours N · n classes », a combined course once, its next period « mêmes
  classes »), breaks as thin rows; today's past lessons dimmed, the current one
  outlined, each with its roll-call state. From `sm` the week grid; a combined
  course placed in several classes is one lesson there, not a clash.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Curriculum, Timetabling}
  alias TeacherAssistant.Academics.{DayOfWeek, LessonGroups, Reference, SchoolCalendar}
  alias TeacherAssistantWeb.School.LessonComponents

  import LessonComponents, only: [hm: 1, status_tag: 1]

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      calendar = Attendance.school_calendar(scope)
      today = Reference.today()
      now = Reference.now()
      periods = Attendance.list_periods(scope)
      grid = Timetabling.teacher_timetable(scope, scope.current_user)

      {:ok,
       assign(socket,
         page_title: gettext("Mon emploi du temps"),
         periods: periods,
         grid: grid,
         lessons: lessons_by_day(grid, periods, calendar.lesson_days),
         labels: scope |> Curriculum.list_units_for_scope() |> LessonComponents.course_labels(),
         service: Timetabling.teacher_service(scope, scope.current_user),
         calendar: calendar,
         days: calendar.lesson_days,
         today: today,
         now: NaiveDateTime.to_time(now),
         today_day: weekday(today),
         roll: today_roll(scope, grid, calendar, today, now)
       )}
    end
  end

  def handle_params(params, _uri, socket) do
    %{days: days, today_day: today_day} = socket.assigns

    day =
      Enum.find(days, &(Atom.to_string(&1) == params["day"])) ||
        if(today_day in days, do: today_day, else: List.first(days))

    {:noreply, assign(socket, :day, day)}
  end

  defp weekday(date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  # Each school day's lessons, grouped (`LessonGroups`), in period order.
  defp lessons_by_day(grid, periods, days) do
    Map.new(days, fn day ->
      lessons =
        for period <- periods,
            period.kind == :lesson,
            slot <- Map.get(grid, {day, period.id}, []),
            do: Map.put(slot, :period, period)

      {day, LessonGroups.group(lessons)}
    end)
  end

  # Today's roll-call states by lesson key (`%{}` on a day without lessons).
  defp today_roll(_scope, grid, _calendar, _today, _now) when map_size(grid) == 0, do: %{}

  defp today_roll(scope, _grid, calendar, today, now) do
    if SchoolCalendar.lesson_day?(calendar, today) do
      scope
      |> Attendance.teacher_lessons(scope.current_user, today, now)
      |> Map.new(&{&1.key, &1.status})
    else
      %{}
    end
  end

  defp day_label(d), do: DayOfWeek.label(d)
  defp day_short(d), do: d |> DayOfWeek.label() |> String.slice(0, 3)

  defp roll_call_path(lesson, today),
    do:
      ~p"/school/classes/#{hd(LessonGroups.class_ids(lesson))}/attendance/#{lesson.period.id}?date=#{Date.to_iso8601(today)}"

  defp cell_slots(grid, day, period_id), do: Map.get(grid, {day, period_id}, [])

  # Two lessons in one cell clash, unless they are the same combined course.
  defp clash?(slots),
    do: slots |> Enum.uniq_by(&(&1.combined_course_id || &1.teaching_context_id)) |> length() > 1

  # The cell's lessons, a combined course once with its classes.
  defp cell_lessons(slots),
    do:
      slots
      |> Enum.group_by(&(&1.combined_course_id || {:solo, &1.teaching_context_id}))
      |> Map.values()
      |> Enum.sort_by(&hd(&1).class_label)

  # « 14 h par semaine · service attendu : 18 h » (service part only when one is set),
  # as parts that each stay on one line.
  defp hours_parts(%{load: load, service: nil}), do: [gettext("%{n} h par semaine", n: load)]

  defp hours_parts(%{load: load, service: service}),
    do: [
      gettext("%{n} h par semaine", n: load),
      gettext("service attendu : %{m} h", m: service)
    ]

  # The day's lessons and the breaks between the first and the last, by start time.
  defp day_items([], _periods), do: []

  defp day_items([first | _] = lessons, periods) do
    from = first.period.start_time
    to = List.last(lessons).period.start_time

    breaks =
      for p <- periods,
          p.kind == :break,
          Time.compare(p.start_time, from) == :gt,
          Time.compare(p.start_time, to) == :lt,
          do: {:break, p}

    (Enum.map(lessons, &{:lesson, &1}) ++ breaks)
    |> Enum.sort_by(fn {_kind, x} -> start_of(x) end, Time)
  end

  defp start_of(%{period: p}), do: p.start_time
  defp start_of(%{start_time: t}), do: t

  # « Cours 4 · 5 classes », « Cours 5 · mêmes classes », « Cours 2 · Salle B12 ».
  defp card_sub(lesson) do
    [
      lesson.period.label,
      cond do
        lesson.hour > 1 and LessonGroups.combined?(lesson) ->
          gettext("mêmes classes")

        LessonGroups.combined?(lesson) ->
          ngettext("%{count} classe", "%{count} classes", length(lesson.members))

        true ->
          nil
      end,
      hd(lesson.members).room_name
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp timing(period, now) do
    cond do
      Time.compare(now, period.end_time) != :lt -> :past
      Time.compare(now, period.start_time) != :lt -> :now
      true -> :next
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-timetable" class="space-y-4 sm:space-y-6">
        <header class="flex items-start justify-between gap-3">
          <div>
            <p class="ta-eyebrow hidden sm:block">{gettext("Semaine type")}</p>
            <h1 class="text-2xl font-semibold leading-[1.1] sm:mt-1.5 sm:text-[2rem]">
              {gettext("Mon emploi du temps")}
            </h1>
            <p
              id="my-timetable-hours"
              class="ta-num mt-1.5 text-[0.85rem] text-base-content/75 sm:text-[0.95rem]"
            >
              <%= for {part, i} <- Enum.with_index(hours_parts(@service)) do %>
                {if i > 0, do: " · "}<span class="whitespace-nowrap">{part}</span>
              <% end %>
            </p>
          </div>
          <a
            id="print-my-timetable"
            href={~p"/school/timetable/me/print"}
            target="_blank"
            aria-label={gettext("Imprimer")}
            title={gettext("Imprimer")}
            class="btn btn-ghost btn-square sm:btn-outline sm:btn-sm sm:w-auto sm:gap-2 sm:px-3"
          >
            <.icon name="hero-printer" class="size-5 sm:size-4" />
            <span class="hidden sm:inline">{gettext("Imprimer")}</span>
          </a>
        </header>

        <%= if @grid == %{} do %>
          <.empty_state
            icon="hero-calendar-days"
            title={gettext("Aucun cours placé pour le moment")}
            message={gettext("Vous n'avez pas encore de créneau dans l'emploi du temps.")}
          />
        <% else %>
          <div id="my-timetable-days" class="space-y-3 sm:hidden">
            <nav
              id="day-tabs"
              role="tablist"
              aria-label={gettext("Jour")}
              class="grid gap-1.5"
              style={"grid-template-columns: repeat(#{length(@days)}, minmax(0, 1fr))"}
            >
              <.link
                :for={day <- @days}
                id={"day-tab-#{day}"}
                role="tab"
                patch={~p"/school/timetable/me?day=#{day}"}
                aria-selected={to_string(day == @day)}
                aria-label={day_label(day)}
                class={[
                  "flex h-12 flex-col items-center justify-center rounded-field border text-xs font-semibold transition-colors",
                  if(day == @day,
                    do: "border-primary bg-primary text-primary-content",
                    else: "border-base-300 hover:bg-base-content/5"
                  )
                ]}
              >
                {day_short(day)}
                <span class="ta-num text-[0.68rem] font-medium opacity-80">
                  {gettext("%{n} c.", n: length(@lessons[day]))}
                </span>
              </.link>
            </nav>

            <h2 class="text-sm font-semibold">
              {day_label(@day)}
              <span :if={@day == @today_day} class="text-primary">· {gettext("aujourd'hui")}</span>
            </h2>

            <p :if={Map.get(@lessons, @day, []) == []} class="ta-leaf text-sm text-base-content/70">
              {gettext("Pas de cours")}
            </p>

            <ol class="flex flex-col gap-2">
              <.day_item
                :for={item <- day_items(Map.get(@lessons, @day, []), @periods)}
                item={item}
                today?={@day == @today_day}
                now={@now}
                today={@today}
                roll={@roll}
                labels={@labels}
              />
            </ol>
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
                            :for={slots <- cell_lessons(cell_slots(@grid, day, period.id))}
                            class={[
                              "mb-1 rounded px-2 py-1.5 last:mb-0",
                              if(clash?(cell_slots(@grid, day, period.id)),
                                do: "bg-error/15 text-error",
                                else: "bg-primary/15"
                              )
                            ]}
                          >
                            <p class="font-semibold leading-tight">
                              {Enum.map_join(slots, ", ", & &1.class_label)}
                            </p>
                            <p class="text-xs text-base-content/70">{hd(slots).subject}</p>
                            <p :if={hd(slots).room_name} class="text-xs text-base-content/70">
                              {hd(slots).room_name}
                            </p>
                            <.link
                              :if={day == @today_day}
                              navigate={
                                ~p"/school/classes/#{hd(slots).class_group_id}/attendance/#{period.id}?date=#{Date.to_iso8601(@today)}"
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

  attr :item, :any, required: true
  attr :today?, :boolean, required: true
  attr :today, :any, required: true
  attr :now, :any, required: true
  attr :roll, :map, required: true
  attr :labels, :map, required: true

  defp day_item(%{item: {:break, period}} = assigns) do
    assigns = assign(assigns, :period, period)

    ~H"""
    <li class="flex items-center gap-3 px-3 py-0.5 text-xs text-base-content/70">
      <span class="ta-num w-12">{hm(@period.start_time)}</span>
      <span>{@period.label}</span>
    </li>
    """
  end

  defp day_item(%{item: {:lesson, lesson}} = assigns) do
    timing = if assigns.today?, do: timing(lesson.period, assigns.now), else: :next

    assigns =
      assign(assigns,
        lesson: lesson,
        timing: timing,
        status: assigns.today? && Map.get(assigns.roll, lesson.key)
      )

    ~H"""
    <li
      id={"lesson-#{@lesson.key}"}
      class={[
        "ta-panel flex items-center gap-3 !p-3 transition-opacity",
        @timing == :now && "!border-2 !border-primary",
        @timing == :past && "opacity-60"
      ]}
    >
      <span class="ta-num flex w-12 shrink-0 flex-col text-xs text-base-content/70">
        {hm(@lesson.period.start_time)}
        <span class="opacity-75">{hm(@lesson.period.end_time)}</span>
      </span>
      <span class="flex min-w-0 flex-1 flex-col gap-0.5">
        <span class="truncate text-[0.95rem] font-semibold">
          {LessonComponents.lesson_title(@lesson, @labels)}
        </span>
        <span class="truncate text-xs text-base-content/70">{card_sub(@lesson)}</span>
      </span>
      <.link
        :if={@status in [:in_progress, :missed]}
        id={"lesson-call-#{@lesson.key}"}
        navigate={roll_call_path(@lesson, @today)}
        class="btn btn-primary btn-sm shrink-0"
      >
        {gettext("Faire l'appel")}
      </.link>
      <span :if={@status in [:done, :on_paper, :not_held]} class="shrink-0">
        <.status_tag status={@status} />
      </span>
    </li>
    """
  end
end
