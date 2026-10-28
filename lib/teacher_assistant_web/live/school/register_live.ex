defmodule TeacherAssistantWeb.School.RegisterLive do
  @moduledoc """
  The class's « Cahier d'appel » tab: one day's roll calls per student (a mark per
  lesson period) and the sequence's absence totals. A conduct manager taps a
  student to justify (or un-justify) that student's day in a drawer.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]
  import TeacherAssistantWeb.Drawer

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.JustificationReason
  alias TeacherAssistantWeb.{Dates, Numbers}

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :register) do
      # The register itself is loaded by handle_params/3 (it always follows mount).
      {:ok,
       socket
       |> assign(
         cg: cg,
         today: TeacherAssistant.Academics.Reference.today(),
         viewing_id: nil,
         can_edit?: TeacherAssistant.Discipline.can_manage_conduct?(scope),
         can_manage_register?: Enrollment.can_manage_register?(scope)
       )
       |> ClassShell.assign_shell()}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp parse_date(nil), do: TeacherAssistant.Academics.Reference.today()

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> TeacherAssistant.Academics.Reference.today()
    end
  end

  defp load_register(socket) do
    scope = socket.assigns.current_scope
    register = Attendance.class_register(scope, socket.assigns.cg, socket.assigns.date)

    sequence =
      case scope.current_academic_year do
        nil -> nil
        year -> Organization.current_sequence(scope, year, socket.assigns.date)
      end

    # One read for the whole class, not one per student.
    class_conduct =
      if sequence,
        do: Attendance.class_conduct(scope, socket.assigns.cg, {:sequence, sequence}),
        else: %{}

    zero = %{justified_hours: Decimal.new(0), unjustified_hours: Decimal.new(0), retards: 0}

    conduct_by_enrollment =
      Map.new(
        register.students,
        &{&1.enrollment_id, Map.get(class_conduct, &1.enrollment_id, zero)}
      )

    assign(socket,
      periods: register.periods,
      students: register.students,
      sequence: sequence,
      conduct_by_enrollment: conduct_by_enrollment,
      viewing: Enum.find(register.students, &(&1.enrollment_id == socket.assigns.viewing_id))
    )
  end

  def handle_params(params, _uri, socket) do
    date = parse_date(params["date"])

    {:noreply, socket |> assign(date: date, viewing_id: nil) |> load_register()}
  end

  def handle_event("pick_date", %{"date" => ""}, socket), do: {:noreply, socket}

  def handle_event("pick_date", %{"date" => date_str}, socket) do
    {:noreply, push_patch(socket, to: day_path(socket.assigns.cg, date_str))}
  end

  def handle_event(
        "open_student",
        %{"id" => enrollment_id},
        %{assigns: %{can_edit?: true}} = socket
      ) do
    {:noreply,
     assign(socket,
       viewing_id: enrollment_id,
       viewing: Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id))
     )}
  end

  def handle_event("open_student", _params, socket), do: {:noreply, socket}

  def handle_event("close_student", _params, socket),
    do: {:noreply, assign(socket, viewing_id: nil, viewing: nil)}

  def handle_event("justify", %{"enrollment_id" => enrollment_id} = params, socket) do
    scope = socket.assigns.current_scope

    with %{} = student <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)) do
      note = presence(params["note"])
      reason = parse_reason(params["reason"])

      case Attendance.justify_day(scope, student.enrollment, socket.assigns.date, reason, note) do
        {:ok, 0} ->
          {:noreply, put_flash(socket, :info, gettext("Aucune absence à justifier ce jour-là."))}

        {:ok, _count} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Absences de la journée justifiées."))
           |> assign(viewing_id: nil)
           |> load_register()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unjustify", %{"enrollment_id" => enrollment_id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = student <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)) do
      case Attendance.unjustify_day(scope, student.enrollment, socket.assigns.date) do
        {:ok, _count} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Justification de la journée annulée."))
           |> assign(viewing_id: nil)
           |> load_register()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp parse_reason(value) do
    Enum.find(JustificationReason.values(), &(Atom.to_string(&1) == value))
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v

  defp day_path(cg, %Date{} = date), do: day_path(cg, Date.to_iso8601(date))
  defp day_path(cg, date_str), do: ~p"/school/classes/#{cg.id}/register?date=#{date_str}"

  defp status_label(nil), do: gettext("—")
  defp status_label(:present), do: gettext("P")
  defp status_label(:absent), do: gettext("A")
  defp status_label(:late), do: gettext("R")
  defp status_label(:sent_home), do: gettext("RF")

  defp status_word(nil), do: gettext("Pas d'appel")
  defp status_word(:present), do: gettext("Présent")
  defp status_word(:absent), do: gettext("Absent")
  defp status_word(:late), do: gettext("En retard")
  defp status_word(:sent_home), do: gettext("Renvoyé pour frais")

  defp mark_class(nil), do: "bg-base-200 text-base-content/70"
  defp mark_class(:present), do: "bg-success/15 text-success"
  defp mark_class(:absent), do: "bg-error/15 text-error"
  defp mark_class(:late), do: "bg-warning/20 text-warning"
  defp mark_class(:sent_home), do: "bg-info/15 text-info"

  defp absent_today?(student), do: Enum.any?(student.cells, fn {_id, s} -> s == :absent end)

  defp unjustified?(%{unjustified_hours: hours}), do: Decimal.gt?(hours, 0)

  # One line of sequence totals for the phone row.
  defp totals_meta(conduct) do
    gettext("Injustifiées %{unjustified} · justifiées %{justified}",
      unjustified: Numbers.hours(conduct.unjustified_hours),
      justified: Numbers.hours(conduct.justified_hours)
    ) <>
      " · " <>
      ngettext("%{count} retard", "%{count} retards", conduct.retards)
  end

  attr :status, :atom, default: nil
  attr :period, :map, required: true
  attr :size, :string, default: "size-7"

  # A period's mark: P (present), A (absent), R (late) or a dash when no roll was called.
  defp mark(assigns) do
    ~H"""
    <span
      class={[
        "inline-grid shrink-0 place-items-center rounded-md text-[0.72rem] font-semibold",
        @size,
        mark_class(@status)
      ]}
      title={"#{@period.label} · #{status_word(@status)}"}
    >
      <span aria-hidden="true">{status_label(@status)}</span>
      <span class="sr-only">{@period.label} : {status_word(@status)}</span>
    </span>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:register}>
        <:actions>
          <.link
            :if={@can_edit? and @cg.paper_roll_call}
            id="roll-sheet-link"
            navigate={~p"/school/classes/#{@cg.id}/roll-sheet"}
            class="btn btn-ghost"
          >
            <.icon name="hero-pencil-square" class="size-4" />
            {gettext("Saisir la feuille")}
          </.link>
          <.link
            :if={@can_edit? and @cg.paper_roll_call}
            id="roll-sheet-print"
            href={~p"/school/classes/#{@cg.id}/roll-sheet/print"}
            target="_blank"
            class="btn btn-ghost"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer la feuille")}
          </.link>
          <.link
            :if={@can_manage_register?}
            navigate={~p"/school/classes/#{@cg.id}/photos"}
            id="go-to-photos"
            class="btn btn-ghost"
          >
            <.icon name="hero-camera" class="size-4" />
            {gettext("Photos")}
          </.link>
        </:actions>

        <div id="register" class="space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <nav
              id="register-day-nav"
              aria-label={gettext("Jour affiché")}
              class="flex items-center gap-1"
            >
              <.link
                id="register-prev-day"
                patch={day_path(@cg, Date.add(@date, -1))}
                class="btn btn-ghost btn-square"
                aria-label={gettext("Jour précédent")}
              >
                <.icon name="hero-chevron-left" class="size-5" />
              </.link>
              <h2
                id="register-date"
                class="min-w-0 px-1 text-center text-lg font-semibold first-letter:uppercase"
              >
                {Dates.long(@date)}
              </h2>
              <.link
                id="register-next-day"
                patch={day_path(@cg, Date.add(@date, 1))}
                class="btn btn-ghost btn-square"
                aria-label={gettext("Jour suivant")}
              >
                <.icon name="hero-chevron-right" class="size-5" />
              </.link>
            </nav>

            <div class="flex items-center gap-2">
              <.link
                :if={@date != @today}
                id="register-today"
                patch={day_path(@cg, @today)}
                class="btn btn-ghost"
              >
                {gettext("Aujourd'hui")}
              </.link>
              <form id="register-date-form" phx-change="pick_date" phx-submit="pick_date">
                <label for="register-date-input" class="sr-only">{gettext("Choisir une date")}</label>
                <input
                  id="register-date-input"
                  type="date"
                  name="date"
                  value={Date.to_iso8601(@date)}
                  class="input input-bordered w-40"
                />
              </form>
            </div>
          </div>

          <p :if={@students != []} class="text-sm text-base-content/70">
            {if @sequence,
              do: gettext("Totaux d'absences de la séquence %{number}.", number: @sequence.number),
              else: gettext("Aucune séquence en cours à cette date : pas de totaux.")}
            <span :if={@can_edit?}>{gettext("Touchez un élève pour justifier sa journée.")}</span>
          </p>

          <%!-- ≥sm: the day's grid --%>
          <div
            :if={@students != []}
            class="hidden overflow-x-auto rounded-box border border-base-300 bg-base-100 sm:block"
          >
            <table id="register-grid" class="table">
              <thead>
                <tr>
                  <th class="w-full min-w-44">{gettext("Élève")}</th>
                  <th
                    :for={{period, i} <- Enum.with_index(@periods, 1)}
                    class="px-1 text-center"
                    title={period.label}
                  >
                    <span aria-hidden="true" class="ta-num">{i}</span>
                    <span class="sr-only">{period.label}</span>
                  </th>
                  <th class="whitespace-nowrap text-right">{gettext("Justifiées")}</th>
                  <th class="whitespace-nowrap text-right">{gettext("Injustifiées")}</th>
                  <th class="whitespace-nowrap text-right">{gettext("Retards")}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={student <- @students}
                  id={"register-row-#{student.enrollment_id}"}
                  class={[
                    @can_edit? && "hover:bg-base-200/60",
                    @viewing && @viewing.enrollment_id == student.enrollment_id && "bg-primary/10"
                  ]}
                >
                  <% conduct = Map.get(@conduct_by_enrollment, student.enrollment_id) %>
                  <td class="max-w-0">
                    <button
                      :if={@can_edit?}
                      type="button"
                      id={"open-student-#{student.enrollment_id}"}
                      phx-click="open_student"
                      phx-value-id={student.enrollment_id}
                      title={student.student_name}
                      class="block w-full truncate text-left font-medium hover:underline"
                    >
                      {student.student_name}
                    </button>
                    <span
                      :if={!@can_edit?}
                      title={student.student_name}
                      class="block truncate font-medium"
                    >
                      {student.student_name}
                    </span>
                  </td>
                  <td
                    :for={period <- @periods}
                    id={"cell-#{student.enrollment_id}-#{period.id}"}
                    class="px-1 text-center"
                  >
                    <.mark status={Map.get(student.cells, period.id)} period={period} size="size-6" />
                  </td>
                  <td class="ta-num whitespace-nowrap text-right">
                    {Numbers.hours(conduct.justified_hours)}
                  </td>
                  <td class={[
                    "ta-num whitespace-nowrap text-right",
                    unjustified?(conduct) && "font-semibold text-error"
                  ]}>
                    {Numbers.hours(conduct.unjustified_hours)}
                  </td>
                  <td class="ta-num whitespace-nowrap text-right">{conduct.retards}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <%!-- <sm: one row per student --%>
          <div
            :if={@students != []}
            id="register-list"
            class="ta-section sm:hidden"
          >
            <.list_row
              :for={student <- @students}
              id={"register-item-#{student.enrollment_id}"}
              phx-click={@can_edit? && "open_student"}
              phx-value-id={student.enrollment_id}
              title={student.student_name}
              meta={totals_meta(Map.get(@conduct_by_enrollment, student.enrollment_id))}
              meta_class={
                unjustified?(Map.get(@conduct_by_enrollment, student.enrollment_id)) && "text-error"
              }
              selected={@viewing && @viewing.enrollment_id == student.enrollment_id}
            >
              <span class="mt-1.5 flex flex-wrap gap-1">
                <.mark
                  :for={period <- @periods}
                  status={Map.get(student.cells, period.id)}
                  period={period}
                  size="size-6"
                />
              </span>
            </.list_row>
          </div>

          <.empty_state
            :if={@students == []}
            icon="hero-user-group"
            title={gettext("Aucun élève inscrit")}
          />
        </div>

        <.drawer
          :if={@viewing}
          id="student-day-drawer"
          eyebrow={Dates.long(@date)}
          title={@viewing.student_name}
          on_close={JS.push("close_student")}
        >
          <section class="space-y-2">
            <h3 class="ta-eyebrow">{gettext("Appels du jour")}</h3>
            <ul class="divide-y divide-base-300 rounded-box border border-base-300">
              <li
                :for={period <- @periods}
                class="flex items-center justify-between gap-3 px-3 py-2 text-sm"
              >
                <span class="truncate">{period.label}</span>
                <span class="flex items-center gap-2">
                  <span class="text-base-content/70">
                    {status_word(Map.get(@viewing.cells, period.id))}
                  </span>
                  <.mark status={Map.get(@viewing.cells, period.id)} period={period} size="size-6" />
                </span>
              </li>
            </ul>
            <p class="text-sm text-base-content/70">
              {totals_meta(Map.get(@conduct_by_enrollment, @viewing.enrollment_id))}
            </p>
          </section>

          <form
            :if={absent_today?(@viewing)}
            id={"justify-form-#{@viewing.enrollment_id}"}
            phx-submit="justify"
            class="space-y-1 border-t border-base-300 pt-4"
          >
            <h3 class="ta-eyebrow mb-2">{gettext("Justifier les absences du jour")}</h3>
            <input type="hidden" name="enrollment_id" value={@viewing.enrollment_id} />
            <.input
              type="select"
              id="justify-reason"
              name="reason"
              label={gettext("Motif")}
              value={nil}
              options={for r <- JustificationReason.values(), do: {JustificationReason.label(r), r}}
              required
            />
            <.input
              id="justify-note"
              name="note"
              value=""
              label={gettext("Précision (optionnelle)")}
            />
            <button
              type="button"
              id={"unjustify-#{@viewing.enrollment_id}"}
              class="btn btn-ghost px-0 text-sm"
              phx-click="unjustify"
              phx-value-enrollment_id={@viewing.enrollment_id}
            >
              {gettext("Annuler la justification")}
            </button>
          </form>
          <p :if={!absent_today?(@viewing)} class="text-sm text-base-content/70">
            {gettext("Aucune absence ce jour-là : rien à justifier.")}
          </p>

          <:footer>
            <button type="button" class="btn btn-ghost" phx-click="close_student">
              {gettext("Fermer")}
            </button>
            <button
              :if={absent_today?(@viewing)}
              type="submit"
              id={"justify-#{@viewing.enrollment_id}"}
              form={"justify-form-#{@viewing.enrollment_id}"}
              class="btn btn-primary"
            >
              {gettext("Justifier")}
            </button>
          </:footer>
        </.drawer>
      </.class_shell>
    </Layouts.app>
    """
  end
end
