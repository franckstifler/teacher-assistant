defmodule TeacherAssistantWeb.School.TimetableEditorLive do
  @moduledoc """
  Censorat → Emploi du temps (spec J4, T01; Vie scolaire redesign §2.5): the whole
  school's timetable, one tab per class. A teacher clash is saved and shown in red with
  fix suggestions (move to a free cell, swap with another lesson of the class, give the
  subject to another free teacher within their service); hours placed against hours
  planned per subject. Combined courses (« regroupé ») are placed and cleared on all
  their classes.

  Spec J3: a room clash and a lesson at a time its teacher is unavailable are shown and
  counted like a teacher clash; a shared room too small for the class is an amber
  warning, not counted. The cell panel picks the lesson's room.

  UX refonte 2026-11-03 « Emploi du temps »: a Classe / Enseignant / Salle switcher —
  the last two are read-only grids built from `school_slots` (editing stays in the
  class view); the class picker groups classes by level with the hours still to
  place; « Reste à placer » lists them per subject, each draggable onto a free cell
  (`TimetableDrop` hook) next to the tap-to-place panel.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Organization, Timetabling}

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
         view: :class,
         teachers: nil,
         teacher_id: nil,
         room_id: nil,
         selected: nil,
         fixes: []
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    cg =
      Enum.find(socket.assigns.classes, &(&1.id == params["class"])) ||
        socket.assigns.cg || List.first(socket.assigns.classes)

    view =
      case params["view"] do
        "teacher" -> :teacher
        "room" -> :room
        _ -> :class
      end

    {:noreply,
     socket
     |> assign(page_title: page_title(cg), cg: cg, view: view, selected: nil)
     |> load()
     |> assign_view(params)}
  end

  # The read-only views: whose week (a teacher with lessons or the teacher role) or
  # which room (an active one).
  defp assign_view(%{assigns: %{view: :teacher}} = socket, params) do
    teachers = socket.assigns.teachers || list_teachers(socket)

    teacher_id =
      Enum.find_value(teachers, &(&1.id == params["teacher"] && &1.id)) ||
        socket.assigns.teacher_id || (List.first(teachers) && List.first(teachers).id)

    assign(socket, teachers: teachers, teacher_id: teacher_id)
  end

  defp assign_view(%{assigns: %{view: :room, rooms: rooms}} = socket, params) do
    room_id =
      Enum.find_value(rooms, &(&1.id == params["room"] && &1.id)) ||
        socket.assigns.room_id || (List.first(rooms) && List.first(rooms).id)

    assign(socket, room_id: room_id)
  end

  defp assign_view(socket, _params), do: socket

  defp list_teachers(socket) do
    busy = MapSet.new(socket.assigns.slots, & &1.teacher_id)

    socket.assigns.current_scope
    |> Accounts.list_members()
    |> Enum.filter(&(:teacher in &1.roles or MapSet.member?(busy, &1.user_id)))
    |> Enum.map(&%{id: &1.user_id, name: User.display_name(&1.user)})
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp page_title(nil), do: gettext("Emploi du temps")
  defp page_title(cg), do: gettext("Emploi du temps · %{class}", class: cg.label)

  defp load(%{assigns: %{cg: nil}} = socket),
    do:
      assign(socket,
        slots: [],
        clashes: %{},
        room_clashes: %{},
        unavailable: MapSet.new(),
        unavailable_cells: MapSet.new(),
        over: %{},
        problems: MapSet.new(),
        rooms: [],
        all_rooms: [],
        room_names: %{},
        count: 0,
        grid: %{},
        tally: [],
        to_place: %{},
        assignments: [],
        fixes: []
      )

  defp load(socket) do
    %{current_scope: scope, cg: cg} = socket.assigns
    slots = Timetabling.school_slots(scope)
    timetable = Timetabling.class_timetable(scope, cg)
    unavailable = Timetabling.unavailability(scope)
    clashes = TimetableConflicts.clashes(slots)
    room_clashes = TimetableConflicts.room_clashes(slots)
    unavailable_cells = TimetableConflicts.unavailable_cells(slots, unavailable)
    all_rooms = Organization.list_rooms(scope)

    assign(socket,
      slots: slots,
      clashes: clashes,
      room_clashes: room_clashes,
      unavailable: unavailable,
      unavailable_cells: unavailable_cells,
      over: TimetableConflicts.over_capacity(slots, Map.new(all_rooms, &{&1.id, &1.capacity})),
      problems:
        clashes
        |> Map.keys()
        |> MapSet.new()
        |> MapSet.union(room_clashes |> Map.keys() |> MapSet.new())
        |> MapSet.union(unavailable_cells),
      rooms: Enum.filter(all_rooms, & &1.active?),
      all_rooms: all_rooms,
      room_names: Map.new(all_rooms, &{&1.id, &1.name}),
      count: TimetableConflicts.count(slots, unavailable),
      grid: timetable.slots,
      tally: timetable.tally,
      to_place: Timetabling.hours_to_place(scope, slots),
      assignments: Curriculum.list_assignments_for_class(scope, cg)
    )
    |> assign_fixes()
  end

  # The selected problem lesson's fixes: moves and swaps, then — for a teacher clash or
  # an unavailable teacher, not a room clash — up to two teachers who could take the
  # whole subject (« Confier à »).
  defp assign_fixes(%{assigns: %{selected: {day, period_id} = cell} = assigns} = socket) do
    with %{teaching_context_id: tc_id} <- assigns.grid[cell],
         true <- problem?(assigns.problems, assigns.cg, day, period_id),
         %{} = tc <- Enum.find(assigns.assignments, &(&1.id == tc_id)) do
      reassigns =
        if clash?(assigns.clashes, assigns.cg, day, period_id) or
             MapSet.member?(assigns.unavailable_cells, {assigns.cg.id, day, period_id}),
           do:
             assigns.current_scope
             |> Timetabling.reassign_candidates(tc, assigns.slots, assigns.unavailable)
             |> Enum.take(2)
             |> Enum.map(&Map.merge(&1, %{kind: :reassign, tc: tc})),
           else: []

      assign(socket, fixes: suggestions(assigns, cell) ++ reassigns)
    else
      _ -> assign(socket, fixes: [])
    end
  end

  defp assign_fixes(socket), do: assign(socket, fixes: [])

  # --- events -------------------------------------------------------------------------

  def handle_event("tab", %{"class" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/timetable?class=#{id}")}

  def handle_event("pick_teacher", %{"teacher" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/timetable?view=teacher&teacher=#{id}")}

  def handle_event("pick_room", %{"room" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/timetable?view=room&room=#{id}")}

  # « Reste à placer »: a subject dropped on a free cell (`TimetableDrop` hook).
  def handle_event("drop_place", %{"tc" => tc_id, "day" => day, "period" => period}, socket) do
    {:noreply, socket} = handle_event("select", %{"day" => day, "period" => period}, socket)

    case socket.assigns.selected do
      nil -> {:noreply, socket}
      cell -> if socket.assigns.grid[cell], do: {:noreply, socket}, else: place(socket, tc_id)
    end
  end

  def handle_event("select", %{"day" => day, "period" => period_id}, socket) do
    with d when not is_nil(d) <- day_atom(day, socket),
         %{} = period <-
           Enum.find(socket.assigns.periods, &(&1.id == period_id and &1.kind == :lesson)),
         true <- SchoolCalendar.open_cell?(socket.assigns.calendar, d, period) do
      {:noreply, socket |> assign(selected: {d, period.id}) |> assign_fixes()}
    else
      _ -> {:noreply, assign(socket, selected: nil, fixes: [])}
    end
  end

  def handle_event("place", %{"tc" => tc_id}, socket), do: place(socket, tc_id)

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
    with {day, period_id} <- socket.assigns.selected,
         {i, ""} <- Integer.parse(n),
         %{} = fix <- Enum.at(socket.assigns.fixes, i) do
      scope = socket.assigns.current_scope

      result =
        case fix do
          %{kind: :move, to: to} ->
            Timetabling.move_slot(scope, socket.assigns.cg, {day, period_id}, to)

          %{kind: :swap, to: to} ->
            Timetabling.swap_slots(scope, socket.assigns.cg, {day, period_id}, to)

          %{kind: :reassign, tc: tc, user: user} ->
            Curriculum.reassign_teacher(scope, tc, user)
        end

      socket =
        if result == :ok,
          do: assign(socket, selected: fix[:to] || socket.assigns.selected),
          else: socket

      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_room", %{"room_id" => room_id}, socket) do
    room_id = if room_id == "", do: nil, else: room_id

    with {day, period_id} <- socket.assigns.selected,
         true <- is_nil(room_id) or Enum.any?(socket.assigns.rooms, &(&1.id == room_id)) do
      socket.assigns.current_scope
      |> Timetabling.set_slot_room(socket.assigns.cg, {day, period_id}, room_id)
      |> after_write(socket)
    else
      _ -> after_write({:error, :invalid}, socket)
    end
  end

  # Places the class's assignment `tc_id` in the selected cell (a combined course: in
  # every member class).
  defp place(socket, tc_id) do
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
    do:
      TimetableConflicts.suggestions(
        assigns.slots,
        open_cells(assigns),
        assigns.cg.id,
        cell,
        assigns.unavailable
      )

  defp clash?(clashes, cg, day, period_id), do: Map.has_key?(clashes, {cg.id, day, period_id})

  # Spec J3: a teacher clash, a room clash or an unavailable teacher.
  defp problem?(problems, cg, day, period_id),
    do: MapSet.member?(problems, {cg.id, day, period_id})

  defp class_has_problem?(problems, cg), do: Enum.any?(problems, fn {id, _, _} -> id == cg.id end)

  # The room shown in a cell: only a shared room (not the class's home room).
  defp shown_room(%{room_id: id, room_name: name}, cg)
       when not is_nil(id) and id != cg.home_room_id,
       do: name

  defp shown_room(_slot, _cg), do: nil

  defp home_room_option(room_names, cg) do
    case room_names[cg.home_room_id] do
      nil -> gettext("Salle de la classe")
      name -> gettext("Salle de la classe (%{room})", room: name)
    end
  end

  # Active rooms, plus the lesson's own room when it was deactivated since.
  defp room_options(all_rooms, selected),
    do: Enum.filter(all_rooms, &(&1.active? or &1.id == selected))

  # The select's value: "" while the lesson is in the class's home room.
  defp selected_room(%{room_id: id}, cg) when id == cg.home_room_id, do: ""
  defp selected_room(%{room_id: id}, _cg), do: id

  defp teacher_unavailable?(assigns, tc) do
    with {day, period_id} <- assigns.selected do
      not TimetableConflicts.available?(assigns.unavailable, tc.teacher_user_id, day, period_id)
    end
  end

  defp label_of(classes, id), do: Enum.find_value(classes, "?", &(&1.id == id && &1.label))

  defp period_of(periods, id), do: Enum.find(periods, &(&1.id == id))

  defp hm(t), do: Calendar.strftime(t, "%H:%M")

  defp fix_text(%{kind: :reassign, user: user, load: load, service: service}, _assigns),
    do:
      gettext("Confier à %{name} · %{load} h / %{service} h",
        name: User.display_name(user),
        load: load,
        service: service
      )

  defp fix_text(%{kind: :move} = fix, assigns), do: fix_label(fix, assigns.periods)

  defp fix_text(%{kind: :swap} = fix, assigns),
    do: fix_label(fix, assigns.periods, assigns.assignments)

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

  defp placed_subjects(tally), do: for(%{status: :exact, subject: s} <- tally, do: s)

  defp cell_title(slot, cg) do
    Enum.join(
      Enum.reject([slot.subject, slot.teacher_name, shown_room(slot, cg)], &is_nil/1),
      " · "
    )
  end

  # « 6e A · 20 h à placer · conflit »
  defp class_suffix(class, to_place, problems) do
    [
      Map.get(to_place, class.id, 0) > 0 &&
        gettext("%{hours} h à placer", hours: Map.get(to_place, class.id, 0)),
      class_has_problem?(problems, class) && gettext("conflit")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp view_label(:class), do: gettext("Classe")
  defp view_label(:teacher), do: gettext("Enseignant")
  defp view_label(:room), do: gettext("Salle")

  defp view_path(:class, %{cg: nil}), do: ~p"/school/timetable"
  defp view_path(:class, %{cg: cg}), do: ~p"/school/timetable?class=#{cg.id}"

  defp view_path(:teacher, %{teacher_id: id}) when is_binary(id),
    do: ~p"/school/timetable?view=teacher&teacher=#{id}"

  defp view_path(:teacher, _assigns), do: ~p"/school/timetable?view=teacher"

  defp view_path(:room, %{room_id: id}) when is_binary(id),
    do: ~p"/school/timetable?view=room&room=#{id}"

  defp view_path(:room, _assigns), do: ~p"/school/timetable?view=room"

  # The read-only grid's cells, `{day, period_id} => [%{title, sub}]`, from `school_slots`.
  defp read_only_cells(%{view: :teacher, teacher_id: id} = assigns) when is_binary(id),
    do: cells_for(assigns, &(&1.teacher_id == id), &label_of(assigns.classes, &1.class_group_id))

  defp read_only_cells(%{view: :room, room_id: id} = assigns) when is_binary(id),
    do: cells_for(assigns, &(&1.room_id == id), &label_of(assigns.classes, &1.class_group_id))

  defp read_only_cells(_assigns), do: %{}

  defp cells_for(assigns, keep?, sub) do
    assigns.slots
    |> Enum.filter(keep?)
    |> Enum.group_by(&{&1.day, &1.period_id}, &%{title: &1.subject, sub: sub.(&1)})
    |> Map.new(fn {cell, views} -> {cell, Enum.uniq(views)} end)
  end

  defp read_only_empty(%{view: :teacher, teachers: []}), do: gettext("Aucun enseignant.")

  defp read_only_empty(%{view: :room, rooms: []}),
    do: gettext("Aucune salle. Ajoutez-en dans Paramètres › Salles.")

  defp read_only_empty(_assigns), do: nil

  attr :view, :atom, required: true
  attr :cells, :map, required: true
  attr :periods, :list, required: true
  attr :calendar, :any, required: true
  attr :empty, :string, default: nil

  defp read_only_grid(assigns) do
    ~H"""
    <p :if={@empty} id="read-only-empty" class="text-sm text-base-content/70">{@empty}</p>
    <div
      :if={!@empty}
      id={"#{@view}-grid"}
      class="overflow-x-auto rounded-box border border-base-300 bg-base-100"
    >
      <table class="table table-sm table-fixed">
        <thead>
          <tr>
            <th class="w-20"></th>
            <th :for={d <- @calendar.lesson_days}>{DayOfWeek.label(d)}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={p <- @periods}>
            <%= if p.kind == :break do %>
              <td
                colspan={length(@calendar.lesson_days) + 1}
                class="py-0.5 text-center text-xs italic text-base-content/70"
              >
                {p.label}
              </td>
            <% else %>
              <td class="whitespace-nowrap text-xs">
                <span class="font-semibold">{p.label}</span>
                <span class="block text-base-content/70">{hm(p.start_time)}</span>
              </td>
              <td :for={d <- @calendar.lesson_days} class="p-1">
                <% views = @cells[{d, p.id}] || [] %>
                <div
                  id={"ro-cell-#{d}-#{p.id}"}
                  class={[
                    "flex min-h-11 flex-col justify-center overflow-hidden rounded-md px-1.5 text-xs leading-tight",
                    cond do
                      not SchoolCalendar.open_cell?(@calendar, d, p) ->
                        "closed-cell bg-base-200/60 text-base-content/70"

                      length(views) > 1 ->
                        "border border-error bg-error/20"

                      views != [] ->
                        "bg-base-300/70"

                      true ->
                        "border border-dashed border-base-300"
                    end
                  ]}
                >
                  <span
                    :if={not SchoolCalendar.open_cell?(@calendar, d, p)}
                    class="text-base-content/70"
                  >
                    {gettext("Fermé")}
                  </span>
                  <span :for={v <- views} class="block truncate">
                    <span class="font-semibold">{v.title}</span>
                    <span class="text-base-content/70">· {v.sub}</span>
                  </span>
                </div>
              </td>
            <% end %>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="timetable-editor" class="space-y-5">
        <.page_header
          eyebrow={
            gettext("Semaine type · %{classes}",
              classes: ngettext("%{count} classe", "%{count} classes", length(@classes))
            )
          }
          title={gettext("Emploi du temps")}
        >
          <:hint>
            <%!-- the verb follows the pointer; the teacher and room views are read-only --%>
            <span :if={@view == :class} class="pointer-coarse:hidden">
              {gettext("Cliquez sur une case pour placer ou déplacer un cours.")}
            </span>
            <span :if={@view == :class} class="hidden pointer-coarse:inline">
              {gettext(
                "Touchez une case pour placer ou déplacer un cours. Sur ordinateur, toute la semaine tient à l'écran."
              )}
            </span>
          </:hint>
          <%!-- The conflict count and « Disponibilités » (its only way in) stay in view;
               the three prints go behind « ⋯ ». --%>
          <:actions>
            <span
              id="conflict-count"
              class={["text-sm font-semibold", if(@count > 0, do: "text-error", else: "text-success")]}
            >
              {if @count > 0,
                do: ngettext("%{count} conflit à résoudre", "%{count} conflits à résoudre", @count),
                else: gettext("Aucun conflit")}
            </span>
            <.link
              id="availability-link"
              navigate={~p"/school/timetable/availability"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-clock" class="size-4" />
              <span class="sm:hidden">{gettext("Disponibilités")}</span>
              <span class="hidden sm:inline">{gettext("Disponibilités des enseignants")}</span>
            </.link>
            <.action_menu id="timetable-menu" label={gettext("Imprimer")} class="ml-auto">
              <:item
                :if={@cg}
                id="print-timetable"
                icon="hero-printer"
                href={~p"/school/classes/#{@cg.id}/timetable/print"}
                target="_blank"
              >
                {gettext("Imprimer la classe")}
              </:item>
              <:item
                id="print-teachers"
                icon="hero-printer"
                href={~p"/school/timetable/teachers/print"}
                target="_blank"
              >
                {gettext("Emplois du temps des enseignants")}
              </:item>
              <:item
                id="print-general"
                icon="hero-printer"
                href={~p"/school/timetable/general/print"}
                target="_blank"
              >
                {gettext("Emploi du temps général")}
              </:item>
            </.action_menu>
          </:actions>
        </.page_header>

        <div id="timetable-toolbar" class="ta-section flex flex-wrap items-center gap-2 p-2.5">
          <nav class="ta-seg" aria-label={gettext("Vue")}>
            <.link
              :for={v <- [:class, :teacher, :room]}
              id={"view-#{v}"}
              patch={view_path(v, assigns)}
              class="ta-seg__btn"
              aria-current={to_string(@view == v)}
            >
              {view_label(v)}
            </.link>
          </nav>
          <.class_picker
            :if={@view == :class && @classes != []}
            id="timetable-class"
            classes={@classes}
            current={@cg && @cg.id}
            to={&~p"/school/timetable?class=#{&1.id}"}
            change="tab"
            select_class="font-semibold"
            suffix={&class_suffix(&1, @to_place, @problems)}
            class="min-w-0 flex-[0_1_22rem]"
          />
          <form
            :if={@view == :teacher && @teachers != []}
            id="timetable-teacher"
            phx-change="pick_teacher"
            class="min-w-0 flex-[0_1_22rem]"
          >
            <select
              id="timetable-teacher-select"
              name="teacher"
              aria-label={gettext("Enseignant")}
              class="select w-full font-semibold"
            >
              <option :for={t <- @teachers} value={t.id} selected={t.id == @teacher_id}>
                {t.name}
              </option>
            </select>
          </form>
          <form
            :if={@view == :room && @rooms != []}
            id="timetable-room"
            phx-change="pick_room"
            class="min-w-0 flex-[0_1_22rem]"
          >
            <select
              id="timetable-room-select"
              name="room"
              aria-label={gettext("Salle")}
              class="select w-full font-semibold"
            >
              <option :for={r <- @rooms} value={r.id} selected={r.id == @room_id}>
                {r.name}
              </option>
            </select>
          </form>
          <span :if={@view != :class} class="text-xs text-base-content/70">
            {gettext("Lecture seule : on modifie l'emploi du temps depuis la vue Classe.")}
          </span>
        </div>

        <.read_only_grid
          :if={@view != :class}
          view={@view}
          cells={read_only_cells(assigns)}
          periods={@periods}
          calendar={@calendar}
          empty={read_only_empty(assigns)}
        />

        <div
          :if={@view == :class && @cg}
          id="timetable-workspace"
          phx-hook="TimetableDrop"
          class="grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,1fr)_300px]"
        >
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
                      class="py-0.5 text-center text-xs italic text-base-content/70"
                    >
                      {p.label}
                    </td>
                  <% else %>
                    <td class="whitespace-nowrap text-xs">
                      <span class="font-semibold">{p.label}</span>
                      <span class="block text-base-content/70">{hm(p.start_time)}</span>
                    </td>
                    <td :for={d <- @calendar.lesson_days} class="p-1">
                      <% slot = @grid[{d, p.id}] %>
                      <%= cond do %>
                        <% not SchoolCalendar.open_cell?(@calendar, d, p) -> %>
                          <div
                            id={"cell-#{d}-#{p.id}"}
                            class="closed-cell flex h-11 items-center rounded bg-base-200/60 px-1.5 text-xs text-base-content/70"
                          >
                            {gettext("Fermé")}
                          </div>
                        <% true -> %>
                          <button
                            id={"cell-#{d}-#{p.id}"}
                            type="button"
                            phx-click="select"
                            phx-value-day={d}
                            phx-value-period={p.id}
                            data-drop-day={!slot && d}
                            data-drop-period={!slot && p.id}
                            title={slot && cell_title(slot, @cg)}
                            class={[
                              "group h-11 w-full overflow-hidden rounded-md px-1.5 text-left text-xs leading-tight transition-colors",
                              problem?(@problems, @cg, d, p.id) &&
                                "clash-cell border border-error bg-error/30",
                              !problem?(@problems, @cg, d, p.id) && slot &&
                                "bg-base-300/70 hover:bg-base-300",
                              !problem?(@problems, @cg, d, p.id) &&
                                Map.has_key?(@over, {@cg.id, d, p.id}) &&
                                "capacity-cell border border-warning",
                              !slot &&
                                "border border-dashed border-base-300 text-base-content/60 hover:border-primary/60",
                              @selected == {d, p.id} && "ring-2 ring-base-content"
                            ]}
                          >
                            <%= if slot do %>
                              <span class="block truncate font-semibold">{slot.subject}</span>
                              <span
                                :if={room = shown_room(slot, @cg)}
                                class="block truncate text-[0.65rem] text-base-content/70"
                              >
                                {room}
                              </span>
                            <% else %>
                              <span class="sr-only">{gettext("Libre")}</span>
                              <span
                                class="hidden text-base font-semibold text-primary group-hover:inline"
                                aria-hidden="true"
                              >
                                +
                              </span>
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
              <% others = @room_clashes[{@cg.id, d, pid}] %>
              <% over = @over[{@cg.id, d, pid}] %>
              <h2 class="font-semibold">
                {DayOfWeek.label(d)} · {p.label} {hm(p.start_time)}–{hm(p.end_time)} · {@cg.label}
              </h2>
              <p class="text-sm">
                {if slot,
                  do: "#{slot.subject} — #{slot.teacher_name}",
                  else: gettext("Créneau libre")}
              </p>

              <%= if slot && clash?(@clashes, @cg, d, pid) do %>
                <p
                  id="conflict-text"
                  class="rounded-[0.5rem] border border-error/55 bg-error/12 p-2.5 text-sm"
                >
                  <b class="text-error">{gettext("Conflit.")}</b>
                  {gettext("%{teacher} enseigne déjà en %{classes} le %{day} à %{time}.",
                    teacher: slot.teacher_name,
                    classes:
                      @clashes[{@cg.id, d, pid}]
                      |> Enum.map(&label_of(@classes, &1))
                      |> Enum.join(", "),
                    day: String.downcase(DayOfWeek.label(d)),
                    time: hm(p.start_time)
                  )}
                </p>
              <% end %>

              <p
                :if={slot && others}
                id="room-conflict-text"
                class="rounded-[0.5rem] border border-error/55 bg-error/12 p-2.5 text-sm"
              >
                <b class="text-error">{gettext("Conflit.")}</b>
                {gettext("%{room} est déjà occupée par %{classes}.",
                  room: slot.room_name,
                  classes: others |> Enum.map(&label_of(@classes, &1)) |> Enum.join(", ")
                )}
              </p>

              <p
                :if={slot && MapSet.member?(@unavailable_cells, {@cg.id, d, pid})}
                id="unavailable-text"
                class="rounded-[0.5rem] border border-error/55 bg-error/12 p-2.5 text-sm"
              >
                <b class="text-error">{gettext("Conflit.")}</b>
                {gettext("%{teacher} n'est pas disponible le %{day} à %{time}.",
                  teacher: slot.teacher_name,
                  day: String.downcase(DayOfWeek.label(d)),
                  time: hm(p.start_time)
                )}
              </p>

              <p
                :if={slot && over}
                id="capacity-text"
                class="rounded-[0.5rem] border border-warning/55 bg-warning/12 p-2.5 text-sm"
              >
                {gettext("%{size} élèves pour %{capacity} places en %{room}.",
                  size: over.size,
                  capacity: over.capacity,
                  room: @room_names[over.room_id]
                )}
              </p>

              <%= if slot && problem?(@problems, @cg, d, pid) do %>
                <p :if={@fixes == []} class="text-sm text-base-content/70">
                  {gettext("Aucune solution automatique")}
                </p>
                <button
                  :for={{fix, i} <- Enum.with_index(@fixes)}
                  id={"fix-#{i}"}
                  type="button"
                  phx-click="fix"
                  phx-value-n={i}
                  class="btn btn-outline btn-sm h-auto w-full justify-start py-1.5 text-left"
                >
                  {fix_text(fix, assigns)}
                </button>
              <% end %>

              <.form
                :if={slot}
                for={%{}}
                id="room-select"
                phx-change="set_room"
                class="flex items-center gap-2"
              >
                <label for="room-select-input" class="text-sm text-base-content/70">
                  {gettext("Salle")}
                </label>
                <select id="room-select-input" name="room_id" class="select select-sm flex-1">
                  <option value="" selected={selected_room(slot, @cg) == ""}>
                    {home_room_option(@room_names, @cg)}
                  </option>
                  <option
                    :for={r <- room_options(@all_rooms, selected_room(slot, @cg))}
                    :if={r.id != @cg.home_room_id}
                    value={r.id}
                    selected={selected_room(slot, @cg) == r.id}
                  >
                    {r.name}
                  </option>
                </select>
              </.form>

              <div class="flex flex-wrap gap-1.5">
                <% busy_for = fn tc -> busy_elsewhere(assigns, tc) end %>
                <button
                  :for={tc <- @assignments}
                  id={"chip-#{tc.id}"}
                  type="button"
                  phx-click="place"
                  phx-value-tc={tc.id}
                  title={
                    cond do
                      c = busy_for.(tc) ->
                        gettext("%{teacher} a déjà cours en %{class}",
                          teacher: User.display_name(tc.teacher),
                          class: c
                        )

                      teacher_unavailable?(assigns, tc) ->
                        gettext("%{teacher} est indisponible à ce créneau",
                          teacher: User.display_name(tc.teacher)
                        )

                      true ->
                        nil
                    end
                  }
                  class={[
                    "badge badge-outline cursor-pointer py-3",
                    (busy_for.(tc) || teacher_unavailable?(assigns, tc)) && "badge-error",
                    slot && slot.teaching_context_id == tc.id && "badge-primary"
                  ]}
                >
                  {tc.subject} {((t = placed(@tally, tc.id)) && t.placed) || 0}/{tc.weekly_hours}
                  <span :if={tc.combined_course_id} class="text-[0.6rem]">{gettext("regroupé")}</span>
                </button>
              </div>
              <button
                :if={slot}
                id="clear-cell"
                type="button"
                phx-click="clear"
                data-confirm={gettext("Vider ce créneau ?")}
                class="btn btn-ghost btn-sm text-error"
              >
                {gettext("Vider le créneau")}
              </button>
            </div>

            <section
              id="hours"
              aria-label={gettext("Reste à placer")}
              class="ta-section flex flex-col gap-1.5 p-3.5"
            >
              <h2 class="ta-eyebrow mb-1">
                {gettext("Reste à placer · %{hours} h", hours: Map.get(@to_place, @cg.id, 0))}
              </h2>
              <div
                :for={t <- Enum.filter(@tally, &(&1.status == :under))}
                id={"todo-#{t.teaching_context_id}"}
                draggable="true"
                data-tc={t.teaching_context_id}
                title={
                  gettext("%{placed}/%{required} h placées", placed: t.placed, required: t.required)
                }
                class="flex min-h-10 cursor-grab items-center gap-2 rounded-lg border border-dashed border-base-content/25 px-2.5 text-sm transition-colors hover:border-primary/60 hover:bg-base-200/60 active:cursor-grabbing"
              >
                <.icon name="hero-bars-2" class="size-3.5 shrink-0 opacity-50" />
                <span class="min-w-0 flex-1 truncate">{t.subject}</span>
                <span class="ta-num text-xs font-semibold text-warning">
                  {t.required - t.placed} h
                </span>
              </div>
              <p
                :if={Enum.any?(@tally, &(&1.status == :over))}
                id="over-heading"
                class="ta-eyebrow mt-2 text-error"
              >
                {gettext("Placées en trop")}
              </p>
              <p
                :for={t <- Enum.filter(@tally, &(&1.status == :over))}
                id={"over-#{t.teaching_context_id}"}
                class="flex items-center gap-2 px-1 text-sm text-error"
              >
                <span class="min-w-0 flex-1 truncate">{t.subject}</span>
                <span class="ta-num text-xs font-semibold">
                  {gettext("+%{hours} h", hours: t.placed - t.required)}
                </span>
              </p>
              <p :if={@tally == []} class="text-sm text-base-content/70">
                {gettext("Aucune matière affectée à cette classe.")}
              </p>
              <p
                :if={Enum.any?(@tally, &(&1.status == :under))}
                class="mt-1 text-xs text-base-content/70 pointer-coarse:hidden"
              >
                {gettext("Glissez une matière dans une case libre, ou touchez une case.")}
              </p>
              <p
                :if={(placed = placed_subjects(@tally)) != []}
                id="placed-subjects"
                class="mt-1 text-xs text-base-content/70"
              >
                {gettext("Placées : %{subjects}", subjects: Enum.join(placed, ", "))}
              </p>
            </section>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
