defmodule TeacherAssistantWeb.School.TimetableLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Permissions

  @days [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         admin?: Permissions.admin?(scope),
         periods: Timetables.list_periods(scope.current_workspace),
         assignments: Assignments.list_for_class(cg),
         days: @days
       )
       |> load_timetable()}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp load_timetable(socket) do
    timetable = Timetables.class_timetable(socket.assigns.cg)
    assign(socket, slots: timetable.slots, tally: timetable.tally)
  end

  def handle_event("place", %{"day" => day, "period_id" => period_id} = params, socket) do
    with true <- socket.assigns.admin?,
         day_atom when not is_nil(day_atom) <- day_atom(day) do
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
  # class's cell at once (`Timetables.place_combined_slot/3`) — a combined
  # course is deliberately one teacher in several classes at once, so this is
  # not a clash. A solo assignment keeps placing only this class's cell,
  # exactly as before.
  defp place_cell(socket, %{combined_course: %CombinedCourse{} = course}, day_atom, period_id) do
    case Timetables.place_combined_slot(course, day_atom, period_id) do
      {:ok, _slots} ->
        {:noreply, load_timetable(socket)}

      {:error, {:teacher_clash, class_label}} ->
        {:noreply, socket |> flash_clash(class_label) |> load_timetable()}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp place_cell(socket, assignment, day_atom, period_id) do
    case Timetables.place_slot(socket.assigns.cg, %{
           day: day_atom,
           period_id: period_id,
           teaching_context_id: assignment.id
         }) do
      {:ok, _slot} ->
        {:noreply, load_timetable(socket)}

      {:error, {:teacher_clash, class_label}} ->
        {:noreply, socket |> flash_clash(class_label) |> load_timetable()}

      {:error, :invalid} ->
        {:noreply, socket}
    end
  end

  # Clearing a cell that holds a combined slot clears it for every member
  # class (`Timetables.clear_combined_slot/3`); otherwise it clears only this
  # class's cell, exactly as before.
  defp clear_cell(socket, day_atom, period_id) do
    case combined_course_at(socket.assigns.assignments, socket.assigns.slots, day_atom, period_id) do
      %CombinedCourse{} = course ->
        :ok = Timetables.clear_combined_slot(course, day_atom, period_id)

      nil ->
        :ok = Timetables.clear_slot(socket.assigns.cg, day_atom, period_id)
    end

    {:noreply, load_timetable(socket)}
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

  defp flash_clash(socket, class_label) do
    put_flash(
      socket,
      :error,
      gettext("This teacher already has a class in %{class} at this period.", class: class_label)
    )
  end

  defp day_atom(day) when day in ~w(monday tuesday wednesday thursday friday saturday),
    do: String.to_existing_atom(day)

  defp day_atom(_), do: nil

  defp day_label(:monday), do: gettext("Lundi")
  defp day_label(:tuesday), do: gettext("Mardi")
  defp day_label(:wednesday), do: gettext("Mercredi")
  defp day_label(:thursday), do: gettext("Jeudi")
  defp day_label(:friday), do: gettext("Vendredi")
  defp day_label(:saturday), do: gettext("Samedi")

  defp status_badge_class(:under), do: "badge-warning"
  defp status_badge_class(:exact), do: "badge-success"
  defp status_badge_class(:over), do: "badge-error"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-timetable" class="space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Emploi du temps")}"}
        />

        <div class="flex justify-end">
          <a
            id="print-class-timetable"
            href={~p"/school/classes/#{@cg.id}/timetable/print"}
            target="_blank"
            class="btn btn-primary btn-sm gap-2"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer")}
          </a>
        </div>

        <div class="overflow-x-auto">
          <table id="timetable-grid" class="table table-zebra">
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
                  <td :for={day <- @days} id={"cell-#{day}-#{period.id}"}>
                    <% slot = @slots[{day, period.id}] %>
                    <%= if @admin? do %>
                      <form phx-change="place">
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
                            {a.subject} — {a.teacher.email}{if a.combined_course,
                              do: " (#{gettext("combiné")})",
                              else: ""}
                          </option>
                        </select>
                      </form>
                    <% else %>
                      <span :if={slot}>{slot.subject}</span>
                    <% end %>
                  </td>
                <% end %>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="ta-leaf space-y-2">
          <h2 class="text-sm font-semibold">{gettext("Heures par matière")}</h2>
          <ul id="timetable-tally" class="space-y-1 text-sm">
            <li :for={row <- @tally} id={"tally-#{row.teaching_context_id}"}>
              <span class={["badge badge-sm", status_badge_class(row.status)]}>
                {row.subject} {row.placed}/{row.required}
              </span>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
