defmodule TeacherAssistantWeb.School.AvailabilityLive do
  @moduledoc """
  Censorat → Disponibilités (spec J3, T03): a teacher's blocked times this year, on the
  weekly grid of the timetable editor. A cell, a whole day, or a morning / afternoon
  (periods starting before / from 13:00) is toggled. A cell holding one of the
  teacher's lessons shows the class: blocking it is allowed and shows up in the editor.
  Admin axis.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Accounts, Attendance, Organization, Timetabling}
  alias TeacherAssistant.Academics.{DayOfWeek, SchoolCalendar}

  @afternoon ~T[13:00:00]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Timetabling.can_edit_timetable?(scope),
         %{} = year <- Organization.current_academic_year(scope) do
      scope = %{scope | current_academic_year: year}

      {:ok,
       assign(socket,
         page_title: gettext("Disponibilités des enseignants"),
         scope: scope,
         calendar: Attendance.school_calendar(scope),
         periods: scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson)),
         teacher: nil
       )
       |> load()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    teacher =
      Enum.find(socket.assigns.teachers, &(&1.id == params["teacher"])) ||
        List.first(socket.assigns.teachers)

    {:noreply, socket |> assign(teacher: teacher) |> load_lessons()}
  end

  defp load(socket) do
    scope = socket.assigns.scope
    blocked = Timetabling.unavailability(scope)

    teachers =
      scope
      |> Accounts.list_members()
      |> Enum.filter(&(:teacher in &1.roles))
      |> Enum.map(& &1.user)
      |> Enum.sort_by(&{not has_blocks?(blocked, &1.id), String.downcase(User.display_name(&1))})

    assign(socket, blocked: blocked, teachers: teachers)
  end

  defp load_lessons(%{assigns: %{teacher: nil}} = socket), do: assign(socket, lessons: %{})

  defp load_lessons(socket),
    do:
      assign(socket,
        lessons: Timetabling.teacher_timetable(socket.assigns.scope, socket.assigns.teacher)
      )

  def handle_event("pick", %{"teacher" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/timetable/availability?teacher=#{id}")}

  def handle_event("toggle", %{"teacher" => id, "day" => day, "period" => period_id}, socket) do
    with %{} = teacher <- known_teacher(socket, id),
         d when not is_nil(d) <- day_atom(socket, day),
         [_] = cells <- open_cells(socket, d, &(&1.id == period_id)) do
      blocked? = not MapSet.member?(socket.assigns.blocked, {teacher.id, d, period_id})
      write(socket, teacher, cells, blocked?)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_group", %{"teacher" => id, "day" => day, "part" => part}, socket) do
    with %{} = teacher <- known_teacher(socket, id),
         d when not is_nil(d) <- day_atom(socket, day),
         [_ | _] = cells <- open_cells(socket, d, part_filter(part)) do
      all_blocked? =
        Enum.all?(cells, fn {d, p} ->
          MapSet.member?(socket.assigns.blocked, {teacher.id, d, p})
        end)

      write(socket, teacher, cells, not all_blocked?)
    else
      _ -> {:noreply, socket}
    end
  end

  defp write(socket, teacher, cells, blocked?) do
    case Timetabling.set_unavailable(socket.assigns.scope, teacher.id, cells, blocked?) do
      :ok ->
        {:noreply, load(socket)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Modification non enregistrée."))}
    end
  end

  defp known_teacher(socket, id), do: Enum.find(socket.assigns.teachers, &(&1.id == id))

  # A lesson day of the calendar named by the event, or nil (never String.to_atom).
  defp day_atom(socket, day),
    do: Enum.find(socket.assigns.calendar.lesson_days, &(Atom.to_string(&1) == day))

  defp part_filter("day"), do: fn _ -> true end
  defp part_filter("morning"), do: &morning?/1
  defp part_filter("afternoon"), do: &(not morning?(&1))
  defp part_filter(_), do: fn _ -> false end

  defp morning?(period), do: Time.compare(period.start_time, @afternoon) == :lt

  # The day's open lesson cells whose period passes `keep?`.
  defp open_cells(socket, day, keep?) do
    for p <- socket.assigns.periods,
        SchoolCalendar.open_cell?(socket.assigns.calendar, day, p),
        keep?.(p),
        do: {day, p.id}
  end

  defp has_blocks?(blocked, user_id), do: Enum.any?(blocked, &(elem(&1, 0) == user_id))

  defp blocked?(blocked, teacher, day, period),
    do: MapSet.member?(blocked, {teacher.id, day, period.id})

  @doc false
  # « Indisponible : lundi, mercredi après-midi, jeudi (2 périodes) », or nil.
  def summary(blocked, user_id, calendar, periods) do
    parts =
      for day <- calendar.lesson_days,
          open = Enum.filter(periods, &SchoolCalendar.open_cell?(calendar, day, &1)),
          ids = for(p <- open, MapSet.member?(blocked, {user_id, day, p.id}), do: p.id),
          ids != [] do
        name = String.downcase(DayOfWeek.label(day))
        morning = for p <- open, morning?(p), do: p.id
        afternoon = for p <- open, not morning?(p), do: p.id

        cond do
          ids == Enum.map(open, & &1.id) ->
            name

          ids == morning ->
            gettext("%{day} matin", day: name)

          ids == afternoon ->
            gettext("%{day} après-midi", day: name)

          true ->
            ngettext("%{day} (%{count} période)", "%{day} (%{count} périodes)", length(ids),
              day: name
            )
        end
      end

    if parts != [], do: gettext("Indisponible : %{days}", days: Enum.join(parts, ", "))
  end

  defp hm(t), do: Calendar.strftime(t, "%H:%M")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="availability" class="space-y-5">
        <.back_header
          back={~p"/school/timetable"}
          back_label={gettext("Emploi du temps")}
          title={gettext("Disponibilités des enseignants")}
          subtitle={
            gettext(
              "Cliquez sur une case, un jour, un matin ou un après-midi pour le bloquer ou le libérer."
            )
          }
        />

        <div class="grid gap-5 lg:grid-cols-[280px_minmax(0,1fr)]">
          <nav id="teacher-picker" class="ta-panel max-h-[70vh] space-y-1 overflow-y-auto p-2">
            <p :if={@teachers == []} class="p-2 text-sm text-base-content/70">
              {gettext("Aucun enseignant pour l'instant.")}
            </p>
            <button
              :for={t <- @teachers}
              id={"teacher-#{t.id}"}
              type="button"
              phx-click="pick"
              phx-value-teacher={t.id}
              class={[
                "w-full rounded-[0.5rem] px-3 py-2 text-left text-sm transition-colors hover:bg-base-200",
                @teacher && t.id == @teacher.id && "bg-primary/15"
              ]}
            >
              <span class="block font-semibold">{User.display_name(t)}</span>
              <% s = summary(@blocked, t.id, @calendar, @periods) %>
              <span :if={s} class="block text-xs text-warning">{s}</span>
            </button>
          </nav>

          <div
            :if={@teacher}
            class="overflow-x-auto rounded-box border border-base-300 bg-base-100"
          >
            <table id="avail-grid" class="table table-sm">
              <thead>
                <tr>
                  <th class="sticky left-0 z-10 bg-base-100"></th>
                  <th :for={d <- @calendar.lesson_days} class="align-top">
                    <button
                      id={"avail-day-#{d}"}
                      type="button"
                      phx-click="toggle_group"
                      phx-value-teacher={@teacher.id}
                      phx-value-day={d}
                      phx-value-part="day"
                      class="btn btn-ghost btn-xs"
                    >
                      {DayOfWeek.label(d)}
                    </button>
                    <div class="mt-1 flex gap-1">
                      <button
                        id={"avail-morning-#{d}"}
                        type="button"
                        phx-click="toggle_group"
                        phx-value-teacher={@teacher.id}
                        phx-value-day={d}
                        phx-value-part="morning"
                        class="btn btn-ghost btn-xs px-1 font-normal"
                      >
                        {gettext("Matin")}
                      </button>
                      <button
                        id={"avail-afternoon-#{d}"}
                        type="button"
                        phx-click="toggle_group"
                        phx-value-teacher={@teacher.id}
                        phx-value-day={d}
                        phx-value-part="afternoon"
                        class="btn btn-ghost btn-xs px-1 font-normal"
                      >
                        {gettext("Après-midi")}
                      </button>
                    </div>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={p <- @periods}>
                  <td class="sticky left-0 z-10 whitespace-nowrap bg-base-100 text-xs">
                    <span class="font-semibold">{p.label}</span>
                    <span class="block text-base-content/70">{hm(p.start_time)}</span>
                  </td>
                  <td :for={d <- @calendar.lesson_days} class="p-1">
                    <% lessons = Map.get(@lessons, {d, p.id}, []) %>
                    <%= if SchoolCalendar.open_cell?(@calendar, d, p) do %>
                      <button
                        id={"avail-#{d}-#{p.id}"}
                        type="button"
                        phx-click="toggle"
                        phx-value-teacher={@teacher.id}
                        phx-value-day={d}
                        phx-value-period={p.id}
                        class={[
                          "h-10 w-full rounded px-1.5 text-left text-xs transition-colors",
                          if(blocked?(@blocked, @teacher, d, p),
                            do: "blocked border border-warning bg-warning/25",
                            else: "border border-dashed border-base-300 hover:bg-base-200"
                          )
                        ]}
                      >
                        <span :if={blocked?(@blocked, @teacher, d, p)} class="block font-semibold">
                          {gettext("Indisponible")}
                        </span>
                        <span :if={lessons != []} class="block truncate text-base-content/70">
                          {Enum.map_join(lessons, ", ", & &1.class_label)}
                        </span>
                      </button>
                    <% else %>
                      <div class="flex h-10 items-center rounded bg-base-200/60 px-1.5 text-xs text-base-content/70">
                        {gettext("Fermé")}
                      </div>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
