defmodule TeacherAssistantWeb.School.TimetableLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.DayOfWeek
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :timetable),
         # Spec J4: editors work in the school-wide editor; others keep this read-only grid.
         false <- Timetabling.can_edit_timetable?(scope) && {:editor, cg} do
      calendar = Attendance.school_calendar(scope)

      {:ok,
       socket
       |> assign(
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
      {:editor, cg} -> {:ok, push_navigate(socket, to: ~p"/school/timetable?class=#{cg.id}")}
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp load_timetable(socket) do
    timetable = Timetabling.class_timetable(socket.assigns.current_scope, socket.assigns.cg)
    assign(socket, slots: timetable.slots, tally: timetable.tally)
  end

  def handle_event("place", %{"day" => day, "period_id" => period_id} = params, socket) do
    with day_atom when not is_nil(day_atom) <- day_atom(day) do
      teaching_context_id = params["teaching_context_id"]

      case teaching_context_id do
        "" ->
          clear_cell(socket, day_atom, period_id)

        _ ->
          case Enum.find(socket.assigns.assignments, &(&1.id == teaching_context_id)) do
            nil ->
              {:noreply, socket}

            assignment ->
              place_cell(socket, assignment, day_atom, period_id)
          end
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # A member of a `CombinedCourse` places the same delivery into EVERY member
  # class's cell at once (`Timetabling.place_combined_slot/4`) — a combined
  # course is deliberately one teacher in several classes at once, so this is
  # not a clash. A solo assignment keeps placing only this class's cell,
  # exactly as before.
  defp place_cell(socket, %{combined_course: %CombinedCourse{} = course}, day_atom, period_id) do
    case Timetabling.place_combined_slot(
           socket.assigns.current_scope,
           course,
           day_atom,
           period_id
         ) do
      {:ok, _slots} ->
        {:noreply, load_timetable(socket)}

      {:error, :closed_cell} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Ce créneau est fermé (jour sans cours ou mercredi après-midi).")
         )
         |> load_timetable()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp place_cell(socket, assignment, day_atom, period_id) do
    case Timetabling.place_slot(socket.assigns.current_scope, socket.assigns.cg, %{
           day: day_atom,
           period_id: period_id,
           teaching_context_id: assignment.id
         }) do
      {:ok, _slot} ->
        {:noreply, load_timetable(socket)}

      {:error, :closed_cell} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Ce créneau est fermé (jour sans cours ou mercredi après-midi).")
         )
         |> load_timetable()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # Clearing a cell that holds a combined slot clears it for every member
  # class (`Timetabling.clear_combined_slot/4`); otherwise it clears only this
  # class's cell, exactly as before.
  defp clear_cell(socket, day_atom, period_id) do
    scope = socket.assigns.current_scope

    result =
      case combined_course_at(
             socket.assigns.assignments,
             socket.assigns.slots,
             day_atom,
             period_id
           ) do
        %CombinedCourse{} = course ->
          Timetabling.clear_combined_slot(scope, course, day_atom, period_id)

        nil ->
          Timetabling.clear_slot(scope, socket.assigns.cg, day_atom, period_id)
      end

    case result do
      :ok -> {:noreply, load_timetable(socket)}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  defp combined_course_at(assignments, slots, day_atom, period_id) do
    with %{teaching_context_id: teaching_context_id} <- slots[{day_atom, period_id}],
         %{combined_course: %CombinedCourse{} = course} <-
           Enum.find(assignments, &(&1.id == teaching_context_id)) do
      course
    else
      _ -> nil
    end
  end

  defp day_atom(day) when day in ~w(monday tuesday wednesday thursday friday saturday),
    do: String.to_existing_atom(day)

  defp day_atom(_), do: nil

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

        <%!-- Phones: the week read day by day; placing lessons needs the grid (≥sm). --%>
        <div id="timetable-days" class="space-y-4 sm:hidden">
          <p :if={@can_edit_timetable?} class="text-sm text-base-content/70">
            {gettext("Pour placer les cours, ouvrez cette page sur un écran plus large.")}
          </p>
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
                        <%= if @can_edit_timetable? do %>
                          <form id={"place-#{day}-#{period.id}"} phx-change="place">
                            <input type="hidden" name="day" value={day} />
                            <input type="hidden" name="period_id" value={period.id} />
                            <select
                              name="teaching_context_id"
                              class="select select-bordered select-xs w-full"
                            >
                              <option value="">{gettext("—")}</option>
                              <option
                                :for={a <- @assignments}
                                value={a.id}
                                selected={slot && slot.teaching_context_id == a.id}
                              >
                                {a.subject} — {User.display_name(a.teacher)}{if a.combined_course,
                                  do: " (#{gettext("combiné")})",
                                  else: ""}
                              </option>
                            </select>
                          </form>
                        <% else %>
                          <span :if={slot}>{slot.subject}</span>
                        <% end %>
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
