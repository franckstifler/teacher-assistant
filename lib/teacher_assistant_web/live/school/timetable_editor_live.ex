defmodule TeacherAssistantWeb.School.TimetableEditorLive do
  @moduledoc """
  Censorat → Emploi du temps (spec J4, T01): the whole school's timetable, one tab per
  class. A teacher clash is saved and shown in red with fix suggestions (move to a free
  cell, swap with another lesson of the class); hours placed against hours planned per
  subject. Combined courses (« regroupé ») are placed and cleared on all their classes.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}

  alias TeacherAssistant.Academics.{
    CombinedCourse,
    DayOfWeek,
    SchoolCalendar,
    SchoolTemplates,
    TimetableConflicts
  }

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Timetabling.can_edit_timetable?(scope),
         %{} = year <- Organization.current_academic_year(scope) do
      classes =
        scope
        |> Enrollment.list_class_groups(year)
        |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)

      calendar = Attendance.school_calendar(scope)

      {:ok,
       assign(socket,
         year: year,
         classes: classes,
         calendar: calendar,
         periods: Attendance.list_periods(scope),
         cg: nil,
         selected: nil
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    cg =
      Enum.find(socket.assigns.classes, &(&1.id == params["class"])) ||
        List.first(socket.assigns.classes)

    {:noreply, socket |> assign(cg: cg, selected: nil) |> load()}
  end

  defp load(%{assigns: %{cg: nil}} = socket),
    do: assign(socket, slots: [], clashes: %{}, count: 0, grid: %{}, tally: [], assignments: [])

  defp load(socket) do
    %{current_scope: scope, cg: cg} = socket.assigns
    slots = Timetabling.school_slots(scope)
    timetable = Timetabling.class_timetable(scope, cg)

    assign(socket,
      slots: slots,
      clashes: TimetableConflicts.clashes(slots),
      count: TimetableConflicts.count(slots),
      grid: timetable.slots,
      tally: timetable.tally,
      assignments: Curriculum.list_assignments_for_class(scope, cg)
    )
  end

  # --- events -------------------------------------------------------------------------

  def handle_event("tab", %{"class" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/timetable?class=#{id}")}

  def handle_event("select", %{"day" => day, "period" => period_id}, socket) do
    with d when not is_nil(d) <- day_atom(day, socket),
         %{} = period <-
           Enum.find(socket.assigns.periods, &(&1.id == period_id and &1.kind == :lesson)),
         true <- SchoolCalendar.open_cell?(socket.assigns.calendar, d, period) do
      {:noreply, assign(socket, selected: {d, period.id})}
    else
      _ -> {:noreply, assign(socket, selected: nil)}
    end
  end

  def handle_event("place", %{"tc" => tc_id}, socket) do
    with {day, period_id} <- socket.assigns.selected,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == tc_id)) do
      scope = socket.assigns.current_scope

      result =
        case tc.combined_course do
          %CombinedCourse{} = course ->
            Timetabling.place_combined_slot(scope, course, day, period_id)

          _ ->
            Timetabling.place_slot(scope, socket.assigns.cg, %{
              day: day,
              period_id: period_id,
              teaching_context_id: tc.id
            })
        end

      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear", _params, socket) do
    with {day, period_id} <- socket.assigns.selected,
         %{teaching_context_id: tc_id} <- socket.assigns.grid[{day, period_id}] do
      scope = socket.assigns.current_scope

      result =
        case Enum.find(socket.assigns.assignments, &(&1.id == tc_id)) do
          %{combined_course: %CombinedCourse{} = course} ->
            Timetabling.clear_combined_slot(scope, course, day, period_id)

          _ ->
            Timetabling.clear_slot(scope, socket.assigns.cg, day, period_id)
        end

      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("fix", %{"n" => n}, socket) do
    with {day, period_id} = cell <- socket.assigns.selected,
         {i, ""} <- Integer.parse(n),
         %{} = fix <- Enum.at(suggestions(socket.assigns, cell), i) do
      scope = socket.assigns.current_scope

      result =
        case fix do
          %{kind: :move, to: to} ->
            Timetabling.move_slot(scope, socket.assigns.cg, {day, period_id}, to)

          %{kind: :swap, to: to} ->
            Timetabling.swap_slots(scope, socket.assigns.cg, {day, period_id}, to)
        end

      socket = if result == :ok, do: assign(socket, selected: fix.to), else: socket
      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  defp after_write(result, socket) when result == :ok or elem(result, 0) == :ok,
    do: {:noreply, load(socket)}

  defp after_write({:error, %Ash.Error.Forbidden{}}, socket),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, reason}, socket),
    do: {:noreply, socket |> put_flash(:error, error_text(reason)) |> load()}

  defp error_text(:closed_cell),
    do: gettext("Ce créneau est fermé (jour sans cours ou mercredi après-midi).")

  defp error_text(:occupied), do: gettext("Le créneau visé n'est plus libre.")
  defp error_text(_), do: gettext("Modification non enregistrée.")

  # --- helpers ----------------------------------------------------------------------------

  # A lesson day of the calendar named by the event, or nil (never String.to_atom).
  defp day_atom(day, socket),
    do: Enum.find(socket.assigns.calendar.lesson_days, &(Atom.to_string(&1) == day))

  defp lesson_periods(periods), do: Enum.filter(periods, &(&1.kind == :lesson))

  defp open_cells(%{calendar: cal, periods: periods}) do
    for day <- cal.lesson_days,
        p <- lesson_periods(periods),
        SchoolCalendar.open_cell?(cal, day, p),
        do: {day, p.id}
  end

  defp suggestions(assigns, cell),
    do: TimetableConflicts.suggestions(assigns.slots, open_cells(assigns), assigns.cg.id, cell)

  defp clash?(clashes, cg, day, period_id), do: Map.has_key?(clashes, {cg.id, day, period_id})

  defp class_has_clash?(clashes, cg),
    do: Enum.any?(clashes, fn {{id, _, _}, _} -> id == cg.id end)

  defp label_of(classes, id), do: Enum.find_value(classes, "?", &(&1.id == id && &1.label))

  defp period_of(periods, id), do: Enum.find(periods, &(&1.id == id))

  defp hm(t), do: Calendar.strftime(t, "%H:%M")

  defp fix_label(%{kind: :move, to: {d, p}}, periods),
    do:
      gettext("Déplacer au %{day} %{period} (créneau libre)",
        day: String.downcase(DayOfWeek.label(d)),
        period: period_of(periods, p).label
      )

  defp fix_label(%{kind: :swap, to: {d, p}, with: o}, periods, assignments) do
    subject = Enum.find_value(assignments, "?", &(&1.id == o.teaching_context_id && &1.subject))

    gettext("Échanger avec %{subject} du %{day} %{period}",
      subject: subject,
      day: String.downcase(DayOfWeek.label(d)),
      period: period_of(periods, p).label
    )
  end

  # Teacher of `tc` already teaching elsewhere at the selected cell (another class, not its own combined course).
  defp busy_elsewhere(assigns, tc) do
    with {day, period_id} <- assigns.selected do
      Enum.find_value(assigns.slots, fn s ->
        (s.teacher_id == tc.teacher_user_id and s.day == day and s.period_id == period_id and
           s.class_group_id != assigns.cg.id and
           (is_nil(tc.combined_course_id) or s.combined_course_id != tc.combined_course_id)) &&
          label_of(assigns.classes, s.class_group_id)
      end)
    end
  end

  defp placed(tally, tc_id), do: Enum.find(tally, &(&1.teaching_context_id == tc_id))

  defp tally_class(:under), do: "text-warning"
  defp tally_class(:exact), do: "text-success"
  defp tally_class(:over), do: "text-error"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="timetable-editor" class="space-y-5">
        <.page_header
          eyebrow={gettext("Censorat · semaine type")}
          title={
            if @cg,
              do: gettext("Emploi du temps · %{class}", class: @cg.label),
              else: gettext("Emploi du temps")
          }
        >
          <:actions>
            <span
              id="conflict-count"
              class={["text-sm font-semibold", if(@count > 0, do: "text-error", else: "text-success")]}
            >
              {if @count > 0,
                do: ngettext("%{count} conflit à résoudre", "%{count} conflits à résoudre", @count),
                else: gettext("Aucun conflit")}
            </span>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap gap-1.5">
          <button
            :for={c <- @classes}
            id={"class-tab-#{c.id}"}
            type="button"
            phx-click="tab"
            phx-value-class={c.id}
            class={["btn btn-xs", if(@cg && c.id == @cg.id, do: "btn-primary", else: "btn-ghost")]}
          >
            {c.label}
            <span :if={class_has_clash?(@clashes, c)} class="size-1.5 rounded-full bg-error"></span>
          </button>
        </div>

        <div :if={@cg} class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_320px]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="editor-grid" class="table table-sm">
              <thead>
                <tr>
                  <th></th>
                  <th :for={d <- @calendar.lesson_days}>{DayOfWeek.label(d)}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={p <- @periods}>
                  <%= if p.kind == :break do %>
                    <td
                      colspan={length(@calendar.lesson_days) + 1}
                      class="py-0.5 text-center text-xs italic text-base-content/50"
                    >
                      {p.label}
                    </td>
                  <% else %>
                    <td class="whitespace-nowrap text-xs">
                      <span class="font-semibold">{p.label}</span>
                      <span class="block text-base-content/60">{hm(p.start_time)}</span>
                    </td>
                    <td :for={d <- @calendar.lesson_days} class="p-1">
                      <% slot = @grid[{d, p.id}] %>
                      <%= cond do %>
                        <% not SchoolCalendar.open_cell?(@calendar, d, p) -> %>
                          <div
                            id={"cell-#{d}-#{p.id}"}
                            class="closed-cell h-11 rounded bg-base-200/60"
                          >
                          </div>
                        <% true -> %>
                          <button
                            id={"cell-#{d}-#{p.id}"}
                            type="button"
                            phx-click="select"
                            phx-value-day={d}
                            phx-value-period={p.id}
                            class={[
                              "h-11 w-full rounded px-1.5 text-left text-xs",
                              clash?(@clashes, @cg, d, p.id) &&
                                "clash-cell border border-error bg-error/30",
                              !clash?(@clashes, @cg, d, p.id) && slot && "bg-primary/15",
                              !slot && "border border-dashed border-base-300 text-base-content/50",
                              @selected == {d, p.id} && "ring-2 ring-base-content"
                            ]}
                          >
                            <%= if slot do %>
                              <span class="block truncate font-semibold">{slot.subject}</span>
                              <span class="block truncate text-base-content/70">{slot.teacher_email}</span>
                            <% else %>
                              {gettext("Libre")}
                            <% end %>
                          </button>
                      <% end %>
                    </td>
                  <% end %>
                </tr>
              </tbody>
            </table>
          </div>

          <aside class="space-y-4">
            <div :if={@selected} id="cell-panel" class="ta-panel space-y-3 p-4">
              <% {d, pid} = @selected %>
              <% p = period_of(@periods, pid) %>
              <% slot = @grid[@selected] %>
              <h2 class="font-semibold">
                {DayOfWeek.label(d)} · {p.label} {hm(p.start_time)}–{hm(p.end_time)} · {@cg.label}
              </h2>
              <p class="text-sm">
                {if slot,
                  do: "#{slot.subject} — #{slot.teacher_email}",
                  else: gettext("Créneau libre")}
              </p>

              <%= if slot && clash?(@clashes, @cg, d, pid) do %>
                <p id="conflict-text" class="text-sm text-error">
                  {gettext("Conflit : %{teacher} a aussi cours en %{classes} à ce créneau.",
                    teacher: slot.teacher_email,
                    classes:
                      @clashes[{@cg.id, d, pid}]
                      |> Enum.map(&label_of(@classes, &1))
                      |> Enum.join(", ")
                  )}
                </p>
                <% fixes = suggestions(assigns, @selected) %>
                <p :if={fixes == []} class="text-sm text-base-content/70">
                  {gettext("Aucune solution automatique")}
                </p>
                <button
                  :for={{fix, i} <- Enum.with_index(fixes)}
                  id={"fix-#{i}"}
                  type="button"
                  phx-click="fix"
                  phx-value-n={i}
                  class="btn btn-outline btn-sm w-full justify-start"
                >
                  {if fix.kind == :move,
                    do: fix_label(fix, @periods),
                    else: fix_label(fix, @periods, @assignments)}
                </button>
              <% end %>

              <div class="flex flex-wrap gap-1.5">
                <% busy_for = fn tc -> busy_elsewhere(assigns, tc) end %>
                <button
                  :for={tc <- @assignments}
                  id={"chip-#{tc.id}"}
                  type="button"
                  phx-click="place"
                  phx-value-tc={tc.id}
                  title={
                    (c = busy_for.(tc)) &&
                      gettext("%{teacher} a déjà cours en %{class}",
                        teacher: tc.teacher.email,
                        class: c
                      )
                  }
                  class={[
                    "badge badge-outline cursor-pointer py-3",
                    busy_for.(tc) && "badge-error",
                    slot && slot.teaching_context_id == tc.id && "badge-primary"
                  ]}
                >
                  {tc.subject} · {(t = placed(@tally, tc.id)) && t.placed}/{tc.weekly_hours} h
                  <span :if={tc.combined_course_id} class="text-[0.6rem]">{gettext("regroupé")}</span>
                </button>
              </div>
              <button
                :if={slot}
                id="clear-cell"
                type="button"
                phx-click="clear"
                class="btn btn-ghost btn-sm text-error"
              >
                {gettext("Vider le créneau")}
              </button>
            </div>

            <div id="hours" class="ta-panel space-y-1 p-4">
              <h2 class="ta-eyebrow">{gettext("Heures par matière")}</h2>
              <div
                :for={t <- @tally}
                id={"hours-#{t.teaching_context_id}"}
                class="flex justify-between text-sm"
              >
                <span>{t.subject}</span>
                <span class={["ta-num", tally_class(t.status)]}>{t.placed}/{t.required} h</span>
              </div>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
