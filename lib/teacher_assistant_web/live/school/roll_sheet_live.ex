defmodule TeacherAssistantWeb.School.RollSheetLive do
  @moduledoc """
  Paper roll call (spec 2026-10-28 §3): the surveillant types a class's returned weekly
  sheet in, on the same grid as the paper. A cell cycles empty → A → R; a lesson column
  is saved only when « Appel fait » is ticked (the teacher's visa), or as « cours non
  assuré ». Lessons taken in the app are shown, never edited here.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  alias TeacherAssistant.{Attendance, Discipline, Enrollment}
  alias TeacherAssistant.Academics.{PaperRollCall, Reference}
  alias TeacherAssistantWeb.RollSheetPrintHTML

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Discipline.can_manage_conduct?(scope) do
      {:ok, socket |> assign(cg: cg) |> ClassShell.assign_shell()}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket) do
    asked = week(params)
    monday = PaperRollCall.within_year(asked, socket.assigns.current_scope.current_academic_year)

    if monday == asked,
      do: {:noreply, load_week(socket, monday)},
      else: {:noreply, push_patch(socket, to: week_path(socket.assigns.cg, monday))}
  end

  # Whether `monday` is the school year's first (`:first`) or last (`:last`) week.
  defp year_edge?(monday, edge, scope) do
    year = scope.current_academic_year
    year != nil and PaperRollCall.within_year(Date.add(monday, step(edge)), year) == monday
  end

  defp step(:first), do: -7
  defp step(:last), do: 7

  defp week(%{"week" => week}) when is_binary(week) do
    case Date.from_iso8601(week) do
      {:ok, date} -> Date.beginning_of_week(date)
      _ -> PaperRollCall.entry_week(Reference.today())
    end
  end

  # The sheet comes back at the end of its week: open on the current one.
  defp week(_params), do: PaperRollCall.entry_week(Reference.today())

  defp load_week(socket, monday) do
    week = Attendance.paper_week(socket.assigns.current_scope, socket.assigns.cg, monday)

    columns =
      for day <- week.days,
          lesson <- day.lessons,
          lesson.state != :app and not lesson.upcoming?,
          into: %{} do
        {key(lesson), column(lesson)}
      end

    assign(socket, week: week, columns: columns)
  end

  defp column(%{state: :paper, marks: marks}),
    do: %{mode: :taken, marks: Map.filter(marks, fn {_id, s} -> s in [:absent, :late] end)}

  defp column(%{state: :not_held}), do: %{mode: :not_held, marks: %{}}
  defp column(_lesson), do: %{mode: :skip, marks: %{}}

  defp key(%{date: date, period: period}), do: {date, period.id}

  def handle_event("cycle", %{"enrollment" => id} = params, socket),
    do: {:noreply, update_mark(socket, params, id, &next/1)}

  def handle_event("cycle_to", %{"enrollment" => id, "value" => value} = params, socket),
    do: {:noreply, update_mark(socket, params, id, fn _ -> mark_from(value) end)}

  def handle_event("toggle_done", params, socket) do
    {:noreply,
     update_column(socket, params, fn
       %{mode: :taken} = c -> %{c | mode: :skip}
       c -> %{c | mode: :taken}
     end)}
  end

  def handle_event("toggle_not_held", params, socket) do
    {:noreply,
     update_column(socket, params, fn
       %{mode: :not_held} = c -> %{c | mode: :skip}
       c -> %{c | mode: :not_held}
     end)}
  end

  def handle_event("save", _params, socket) do
    %{current_scope: scope, cg: cg, week: week, columns: columns} = socket.assigns

    columns =
      for {{date, period_id}, column} <- columns,
          do: %{date: date, period_id: period_id, mode: column.mode, marks: column.marks}

    case Attendance.save_paper_week(scope, cg, week.monday, columns) do
      {:ok, _counts} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Feuille enregistrée."))
         |> load_week(week.monday)}

      {:error, :forbidden} ->
        {:noreply, TeacherAssistantWeb.Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Feuille non enregistrée."))}
    end
  end

  defp next(nil), do: :absent
  defp next(:absent), do: :late
  defp next(:late), do: nil

  defp mark_from("a"), do: :absent
  defp mark_from("r"), do: :late
  defp mark_from(_), do: nil

  # Only an editable column, and never a student sent home that day.
  defp update_mark(socket, params, id, fun) do
    with {:ok, key} <- parse_key(params),
         %{} = lesson <- find_lesson(socket.assigns.week, key),
         false <- MapSet.member?(lesson.sent_home, id),
         true <- id in Enum.map(socket.assigns.week.students, & &1.enrollment_id) do
      update_column(socket, params, fn column ->
        marks =
          case fun.(Map.get(column.marks, id)) do
            nil -> Map.delete(column.marks, id)
            mark -> Map.put(column.marks, id, mark)
          end

        %{column | marks: marks}
      end)
    else
      _ -> socket
    end
  end

  defp update_column(socket, params, fun) do
    with {:ok, key} <- parse_key(params),
         %{} = column <- Map.get(socket.assigns.columns, key) do
      assign(socket, :columns, Map.put(socket.assigns.columns, key, fun.(column)))
    else
      _ -> socket
    end
  end

  defp parse_key(%{"date" => date, "period" => period_id}) do
    case Date.from_iso8601(date) do
      {:ok, date} -> {:ok, {date, period_id}}
      _ -> :error
    end
  end

  defp parse_key(_params), do: :error

  defp find_lesson(week, {date, period_id}) do
    Enum.find_value(week.days, fn day ->
      Enum.find(day.lessons, &(&1.date == date and &1.period.id == period_id))
    end)
  end

  # « Lundi 15 · MATH » for each column with A or R typed but not ticked, apart
  # (`:kept`) when it was typed in earlier: its saved entries stay as they are.
  defp unticked(week, columns) do
    for day <- week.days,
        lesson <- day.lessons,
        %{mode: :skip, marks: marks} <- [Map.get(columns, key(lesson))],
        map_size(marks) > 0 or lesson.state == :paper,
        reduce: %{new: [], kept: []} do
      acc ->
        group = if lesson.state == :paper, do: :kept, else: :new
        Map.update!(acc, group, &(&1 ++ ["#{day.label} · #{lesson.code}"]))
    end
  end

  defp mark_text(:absent), do: "A"
  defp mark_text(:late), do: "R"
  defp mark_text(_), do: ""

  defp cell_id(student, lesson),
    do: "cell-#{student.enrollment_id}-#{lesson.date}-#{lesson.period.id}"

  defp day_span(%{closed: nil, lessons: lessons}), do: max(length(lessons), 1)
  defp day_span(_day), do: 1

  defp week_path(cg, monday),
    do: ~p"/school/classes/#{cg.id}/roll-sheet?week=#{Date.to_iso8601(monday)}"

  def render(assigns) do
    lessons = for day <- assigns.week.days, lesson <- day.lessons, do: lesson

    assigns =
      assign(assigns,
        unticked: unticked(assigns.week, assigns.columns),
        cols: lessons |> Enum.with_index() |> Map.new(fn {l, i} -> {key(l), i} end)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:register}>
        <:actions>
          <.link
            id="roll-sheet-print-week"
            href={
              ~p"/school/classes/#{@cg.id}/roll-sheet/print?week=#{Date.to_iso8601(@week.monday)}"
            }
            target="_blank"
            class="btn btn-ghost"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer la feuille")}
          </.link>
        </:actions>

        <div id="roll-sheet" class="space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <nav aria-label={gettext("Semaine affichée")} class="flex items-center gap-1">
              <.link
                :if={!year_edge?(@week.monday, :first, @current_scope)}
                id="roll-sheet-prev"
                patch={week_path(@cg, Date.add(@week.monday, -7))}
                class="btn btn-ghost btn-square"
                aria-label={gettext("Semaine précédente")}
              >
                <.icon name="hero-chevron-left" class="size-5" />
              </.link>
              <h2 class="text-base font-semibold">{RollSheetPrintHTML.week_label(@week)}</h2>
              <.link
                :if={!year_edge?(@week.monday, :last, @current_scope)}
                id="roll-sheet-next"
                patch={week_path(@cg, Date.add(@week.monday, 7))}
                class="btn btn-ghost btn-square"
                aria-label={gettext("Semaine suivante")}
              >
                <.icon name="hero-chevron-right" class="size-5" />
              </.link>
            </nav>
            <p class="text-sm text-base-content/70">
              {gettext("Cliquez une case : vide → A → R. Cochez « Appel fait » quand le visa y est.")}
            </p>
          </div>

          <div class="ta-panel overflow-x-auto !p-0">
            <table id="roll-sheet-grid" class="table table-sm w-max" phx-hook=".RollSheetKeys">
              <thead>
                <tr>
                  <th class="sticky left-0 z-10 bg-base-100" rowspan="3">{gettext("Élève")}</th>
                  <th
                    :for={day <- @week.days}
                    colspan={day_span(day)}
                    class="border-l border-base-300 text-center"
                  >
                    {day.label}
                  </th>
                </tr>
                <tr>
                  <%= for day <- @week.days do %>
                    <th :if={day.closed} class="border-l border-base-300 text-center italic">
                      {day.closed}
                    </th>
                    <th :if={!day.closed and day.lessons == []} class="border-l border-base-300"></th>
                    <th
                      :for={lesson <- day.lessons}
                      class="border-l border-base-300 text-center"
                      title={lesson.subject}
                    >
                      {lesson.code}
                    </th>
                  <% end %>
                </tr>
                <tr>
                  <%= for day <- @week.days do %>
                    <th :if={day.closed != nil or day.lessons == []} class="border-l border-base-300">
                    </th>
                    <th :for={lesson <- day.lessons} class="border-l border-base-300 align-top">
                      <.column_controls
                        lesson={lesson}
                        column={Map.get(@columns, key(lesson))}
                        cg={@cg}
                      />
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <tr :for={student <- @week.students}>
                  <td class="sticky left-0 z-10 max-w-48 truncate bg-base-100">
                    <span class="ta-num text-base-content/60">{student.number}</span>
                    {student.student_name}
                  </td>
                  <%= for day <- @week.days do %>
                    <td
                      :if={day.closed != nil or day.lessons == []}
                      class="border-l border-base-300 bg-base-200/60"
                    >
                    </td>
                    <td
                      :for={lesson <- day.lessons}
                      class="border-l border-base-300 p-0.5 text-center"
                    >
                      <.mark_cell
                        student={student}
                        lesson={lesson}
                        col={@cols[key(lesson)]}
                        column={Map.get(@columns, key(lesson))}
                      />
                    </td>
                  <% end %>
                </tr>
              </tbody>
            </table>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".RollSheetKeys">
              // Arrows move between cells; « a » / « r » set the mark, Backspace clears it.
              export default {
                mounted() {
                  this.el.addEventListener("keydown", (e) => {
                    const cell = e.target.closest("button[data-cell]")
                    if (!cell) return
                    const row = +cell.dataset.row, col = +cell.dataset.col
                    const moves = {ArrowLeft: [0, -1], ArrowRight: [0, 1], ArrowUp: [-1, 0], ArrowDown: [1, 0]}
                    if (moves[e.key]) {
                      e.preventDefault()
                      const [dr, dc] = moves[e.key]
                      const next = this.el.querySelector(`button[data-cell][data-row="${row + dr}"][data-col="${col + dc}"]`)
                      if (next) next.focus()
                      return
                    }
                    const value = {a: "a", A: "a", r: "r", R: "r", Backspace: "", Delete: ""}[e.key]
                    if (value === undefined || cell.disabled) return
                    e.preventDefault()
                    this.pushEvent("cycle_to", {...cell.dataset, value})
                  })
                }
              }
            </script>
          </div>

          <div
            :if={@unticked.kept != []}
            id="kept-warning"
            role="status"
            class="alert text-sm"
          >
            <.icon name="hero-information-circle" class="size-4" />
            <span>
              {gettext("Sans « Appel fait », ces cours gardent la saisie déjà enregistrée :")}
              {Enum.join(@unticked.kept, ", ")}
            </span>
          </div>

          <div
            :if={@unticked.new != []}
            id="unticked-warning"
            role="status"
            class="alert alert-warning text-sm"
          >
            <.icon name="hero-exclamation-triangle" class="size-4" />
            <span>
              {gettext(
                "Ces cours ont des absences mais pas « Appel fait » ; ils ne seront pas enregistrés :"
              )}
              {Enum.join(@unticked.new, ", ")}
            </span>
          </div>

          <div class="flex justify-end">
            <button id="save-week" type="button" phx-click="save" class="btn btn-primary">
              {gettext("Enregistrer la semaine")}
            </button>
          </div>
        </div>
      </.class_shell>
    </Layouts.app>
    """
  end

  attr :lesson, :map, required: true
  attr :column, :map, default: nil
  attr :cg, :map, required: true

  defp column_controls(%{lesson: %{upcoming?: true}} = assigns) do
    ~H"""
    <span class="text-[0.65rem] font-normal text-base-content/50">{gettext("À venir")}</span>
    """
  end

  defp column_controls(%{column: nil} = assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/school/classes/#{@cg.id}/attendance/#{@lesson.period.id}?date=#{Date.to_iso8601(@lesson.date)}"
      }
      class="badge badge-success badge-sm whitespace-nowrap"
      title={gettext("Appel fait dans l'application")}
    >
      {gettext("app")}
    </.link>
    """
  end

  defp column_controls(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <label class="flex cursor-pointer flex-col items-center text-[0.65rem] font-normal">
        <input
          id={"done-#{@lesson.date}-#{@lesson.period.id}"}
          type="checkbox"
          class="checkbox checkbox-sm checkbox-primary"
          checked={@column.mode == :taken}
          phx-click="toggle_done"
          phx-value-date={@lesson.date}
          phx-value-period={@lesson.period.id}
        />
        {gettext("Appel fait")}
      </label>
      <button
        id={"not-held-#{@lesson.date}-#{@lesson.period.id}"}
        type="button"
        phx-click="toggle_not_held"
        phx-value-date={@lesson.date}
        phx-value-period={@lesson.period.id}
        aria-pressed={to_string(@column.mode == :not_held)}
        aria-label={gettext("Cours non assuré")}
        title={gettext("Cours non assuré")}
        class={[
          "rounded px-1 text-[0.65rem] font-normal transition-colors",
          if(@column.mode == :not_held,
            do: "bg-base-content text-base-100",
            else: "text-base-content/60 hover:bg-base-200"
          )
        ]}
      >
        {gettext("Non assuré")}
      </button>
    </div>
    """
  end

  attr :student, :map, required: true
  attr :lesson, :map, required: true
  attr :col, :integer, default: 0
  attr :column, :map, default: nil

  defp mark_cell(%{lesson: %{upcoming?: true}} = assigns) do
    ~H"""
    <span class="mx-auto grid h-9 min-w-9 place-items-center rounded border border-dashed border-base-300"></span>
    """
  end

  defp mark_cell(%{column: nil} = assigns) do
    ~H"""
    <span class="mx-auto grid h-9 min-w-9 place-items-center rounded bg-success/15 text-sm font-semibold text-success">
      {mark_text(@lesson.marks[@student.enrollment_id])}
    </span>
    """
  end

  defp mark_cell(assigns) do
    assigns =
      assign(assigns,
        sent_home?: MapSet.member?(assigns.lesson.sent_home, assigns.student.enrollment_id),
        mark: assigns.column.marks[assigns.student.enrollment_id]
      )

    ~H"""
    <button
      id={cell_id(@student, @lesson)}
      type="button"
      data-cell
      data-row={@student.number}
      data-col={@col}
      data-enrollment={@student.enrollment_id}
      data-date={@lesson.date}
      data-period={@lesson.period.id}
      phx-click="cycle"
      phx-value-enrollment={@student.enrollment_id}
      phx-value-date={@lesson.date}
      phx-value-period={@lesson.period.id}
      disabled={@sent_home? or @column.mode == :not_held}
      aria-label={"#{@student.student_name} · #{TeacherAssistantWeb.Dates.short(@lesson.date)} · #{@lesson.code}"}
      class={[
        "mx-auto grid h-9 min-w-9 place-items-center rounded border text-sm font-semibold transition-colors",
        "focus-visible:outline-2 focus-visible:outline-primary disabled:cursor-not-allowed",
        cond do
          @sent_home? -> "border-transparent px-1 text-[0.65rem] font-normal text-base-content/60"
          @column.mode == :not_held -> "border-dashed border-base-300 bg-base-200/60"
          @mark == :absent -> "border-error bg-error text-error-content"
          @mark == :late -> "border-warning bg-warning text-warning-content"
          true -> "border-base-300 hover:bg-base-200"
        end
      ]}
    >{if @sent_home?, do: gettext("Renvoyé"), else: mark_text(@mark)}</button>
    """
  end
end
