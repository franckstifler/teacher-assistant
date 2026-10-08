defmodule TeacherAssistantWeb.School.DayLive do
  @moduledoc """
  Surveillant général → Aujourd'hui (spec G, V01–V04, V06; Vie scolaire redesign
  §2.1): today's roll calls as a classes × periods grid, the missed roll calls
  with « Relancer », and the school's latest sanctions. Absences are justified on
  `/school/absences`. The surveillant space's home.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.School.SchoolLifeComponents, only: [hm: 1, teacher_name: 1]

  alias TeacherAssistant.{Attendance, Discipline}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.{Authz, Dates, SanctionLabels}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Discipline.can_manage_conduct?(scope) do
      {:ok, load(socket)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    today = Reference.today()
    now = Reference.now()

    sequence_rows =
      case Attendance.current_sequence_range(scope, today) do
        nil -> []
        {first, last} -> Attendance.absence_days(scope, first, last, today)
      end

    assign(socket,
      today: today,
      now: now,
      day: Attendance.school_day(scope, today, now),
      reminded: Attendance.reminded_slot_ids(scope, today),
      day_off: Attendance.day_off(scope, today),
      absent_students: sequence_rows |> Enum.filter(&(&1.date == today)) |> length(),
      to_justify: Enum.count(sequence_rows, &(not &1.justified?)),
      lates: Attendance.late_count(scope, today),
      sanctions: Enum.take(Discipline.recent_sanctions!(scope: scope), 3)
    )
  end

  def handle_event("remind", %{"slot" => slot_id}, socket) do
    scope = socket.assigns.current_scope
    missed = Enum.find(socket.assigns.day.missed, &(&1.slot_id == slot_id))

    case missed && Attendance.remind_roll_call(scope, slot_id, socket.assigns.today) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Rappel envoyé à %{teacher}.", teacher: teacher_name(missed.teacher))
         )
         |> load()}

      {:error, :already_reminded} ->
        {:noreply, load(socket)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  defp no_lessons_title({:holiday, label}), do: gettext("Jour férié : %{label}", label: label)
  defp no_lessons_title(_), do: gettext("Pas de cours aujourd'hui")

  def render(assigns) do
    assigns =
      assign(assigns,
        current: current_period(assigns.day.periods, assigns.now),
        done: count_status(assigns.day, :done)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-day" class="flex flex-col gap-5">
        <.page_header
          eyebrow={
            gettext("%{date} · %{time}",
              date: Dates.long(@today),
              time: Calendar.strftime(@now, "%H:%M")
            )
          }
          title={gettext("Aujourd'hui")}
        >
          <:actions>
            <.link
              id="to-absences"
              navigate={~p"/school/absences"}
              class="btn btn-outline btn-sm"
            >
              {gettext("Absences à justifier · %{count}", count: @to_justify)}
            </.link>
          </:actions>
        </.page_header>

        <.kpi_row>
          <.kpi
            id="kpi-calls"
            label={gettext("Appels faits")}
            value={"#{@done} / #{@done + length(@day.missed)}"}
            sub={
              ngettext(
                "%{count} non fait à %{time}",
                "%{count} non faits à %{time}",
                length(@day.missed),
                time: Calendar.strftime(@now, "%H:%M")
              )
            }
            tone="text-primary"
          />
          <.kpi
            id="kpi-absents"
            label={gettext("Absents")}
            value={to_string(@absent_students)}
            sub={gettext("élèves sur au moins un créneau")}
          />
          <.kpi
            id="kpi-lates"
            label={gettext("Retards")}
            value={to_string(@lates)}
            sub={first_period_text(@day.periods)}
            tone="text-warning"
          />
          <.kpi
            id="kpi-to-justify"
            label={gettext("À justifier")}
            value={to_string(@to_justify)}
            sub={gettext("sur la séquence en cours")}
            tone="text-error"
          />
        </.kpi_row>

        <div :if={@day.rows == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={no_lessons_title(@day_off)} />
        </div>

        <div :if={@day.rows != []} class="ta-panel flex flex-col gap-2.5 overflow-x-auto">
          <div class="flex flex-wrap items-center justify-between gap-3.5">
            <h2 class="text-[1.05rem] font-semibold">
              {gettext("Appels par créneau · nombre d'absents")}
            </h2>
            <div id="grid-legend" class="flex gap-3 text-[0.76rem] text-base-content/80">
              <span>{gettext("· pas de cours")}</span>
              <span class="text-error">{gettext("? appel non fait")}</span>
              <span class="text-warning">{gettext("… en cours")}</span>
            </div>
          </div>
          <div
            id="roll-call-grid"
            class="grid gap-[3px]"
            style={"grid-template-columns: 62px repeat(#{length(@day.periods)}, minmax(54px, 1fr)); min-width: #{62 + length(@day.periods) * 57}px"}
          >
            <span></span>
            <span
              :for={p <- @day.periods}
              class={[
                "ta-num flex flex-col items-center py-[3px] text-[0.66rem] font-semibold",
                if(@current && @current.id == p.id, do: "text-warning", else: "text-base-content/75")
              ]}
            >
              <span class="truncate">{p.label}</span>
              <span class="font-normal">{hm(p.start_time)}</span>
            </span>
            <%= for row <- @day.rows do %>
              <span
                id={"grid-#{row.class_group.id}"}
                class="flex items-center truncate text-[0.82rem] font-semibold"
              >
                {row.class_group.label}
              </span>
              <.grid_cell :for={p <- @day.periods} cell={row.cells[p.id]} />
            <% end %>
          </div>
        </div>

        <div class="grid items-start gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr))]">
          <div id="missed-roll-calls" class="ta-panel flex flex-col gap-0.5">
            <div class="flex items-baseline justify-between gap-2 pb-1">
              <h2 class="text-[1.05rem] font-semibold">{gettext("Appels non faits")}</h2>
              <span class="ta-num text-[0.75rem] text-error">{length(@day.missed)}</span>
            </div>
            <p :if={@day.missed == []} class="py-2 text-sm text-base-content/70">
              {gettext("Tous les appels passés sont faits.")}
            </p>
            <div
              :for={m <- @day.missed}
              id={"missed-#{m.class_group.id}-#{m.period.id}"}
              class="ta-row-rule flex items-center gap-2.5 py-2"
            >
              <div class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="text-[0.9rem] font-semibold">
                  {m.class_group.label} · <span class="ta-num">{hm(m.period.start_time)}</span>
                  · {m.subject}
                </span>
                <span class="text-[0.76rem] text-base-content/75">
                  {teacher_name(m.teacher)} · {gettext("créneau terminé")}
                </span>
              </div>
              <span
                :if={MapSet.member?(@reminded, m.slot_id)}
                id={"reminded-#{m.slot_id}"}
                class="flex-none text-[0.76rem] font-semibold text-primary"
              >
                {gettext("Relancé ✓")}
              </span>
              <button
                :if={not MapSet.member?(@reminded, m.slot_id)}
                id={"remind-#{m.slot_id}"}
                type="button"
                class="btn btn-outline btn-xs flex-none"
                phx-click="remind"
                phx-value-slot={m.slot_id}
                phx-disable-with={gettext("Envoi…")}
              >
                {gettext("Relancer")}
              </button>
            </div>
          </div>

          <div id="recent-sanctions" class="ta-panel flex flex-col gap-0.5">
            <div class="flex items-baseline justify-between gap-2 pb-1">
              <h2 class="text-[1.05rem] font-semibold">{gettext("Sanctions récentes")}</h2>
              <.link
                id="all-sanctions"
                navigate={~p"/school/sanctions"}
                class="text-[0.8rem] font-semibold text-info hover:underline"
              >
                {gettext("Toutes →")}
              </.link>
            </div>
            <p :if={@sanctions == []} class="py-2 text-sm text-base-content/70">
              {gettext("Aucune sanction")}
            </p>
            <.link
              :for={s <- @sanctions}
              id={"sanction-#{s.id}"}
              navigate={~p"/school/classes/#{s.enrollment.class_group_id}/discipline"}
              class="ta-row-rule flex flex-col gap-0.5 py-2 transition-colors hover:text-primary"
            >
              <span class="text-[0.9rem] font-semibold">
                {s.enrollment.student.full_name} · {s.enrollment.class_group.label}
              </span>
              <span class="text-[0.76rem] text-base-content/75">
                {sanction_text(s)} ·
                <b :if={is_nil(s.parents_notified_on)} class="text-warning">
                  {gettext("parents à notifier")}
                </b>
                <span :if={s.parents_notified_on}>{notified_text(s.parents_notified_on, @today)}</span>
              </span>
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :cell, :map, default: nil

  defp grid_cell(%{cell: nil} = assigns),
    do:
      ~H|<span class="ta-num grid h-[30px] place-items-center text-[0.76rem] text-base-content/45">·</span>|

  defp grid_cell(assigns) do
    ~H"""
    <span
      title={cell_title(@cell)}
      class={[
        "ta-num grid h-[30px] place-items-center rounded-[0.35rem] border text-[0.76rem] font-semibold",
        cell_class(@cell)
      ]}
    >
      {cell_text(@cell)}
    </span>
    """
  end

  defp cell_class(%{status: :done, absent: 0}), do: "border-transparent bg-base-200 text-primary"

  defp cell_class(%{status: :done, absent: n}) when n >= 3,
    do: "border-transparent bg-base-200 text-error"

  defp cell_class(%{status: :done}), do: "border-transparent bg-base-200"
  defp cell_class(%{status: :missed}), do: "border-transparent bg-error text-error-content"
  defp cell_class(%{status: :in_progress}), do: "border-warning text-warning"
  defp cell_class(%{status: :upcoming}), do: "border-dashed border-base-300"

  defp cell_text(%{status: :done, absent: n}), do: n
  defp cell_text(%{status: :missed}), do: "?"
  defp cell_text(%{status: :in_progress}), do: "…"
  defp cell_text(%{status: :upcoming}), do: ""

  defp cell_title(%{status: :done, absent: n} = cell),
    do: "#{ngettext("%{count} absent", "%{count} absents", n)} · #{cell_detail(cell)}"

  defp cell_title(%{status: :missed} = cell),
    do: "#{gettext("Appel non fait")} · #{cell_detail(cell)}"

  defp cell_title(%{status: :in_progress} = cell),
    do: "#{gettext("En cours")} · #{cell_detail(cell)}"

  defp cell_title(%{status: :upcoming} = cell), do: "#{gettext("À venir")} · #{cell_detail(cell)}"

  defp cell_detail(cell), do: "#{cell.subject} · #{teacher_name(cell.teacher)}"

  defp current_period(periods, now) do
    time = NaiveDateTime.to_time(now)

    Enum.find(periods, fn p ->
      Time.compare(p.start_time, time) != :gt and Time.compare(time, p.end_time) == :lt
    end)
  end

  defp count_status(day, status),
    do:
      Enum.count(for(row <- day.rows, {_id, cell} <- row.cells, do: cell.status), &(&1 == status))

  # « depuis 07:30 »: the school's first lesson.
  defp first_period_text([]), do: nil
  defp first_period_text([first | _]), do: gettext("depuis %{time}", time: hm(first.start_time))

  defp sanction_text(s) do
    [SanctionLabels.sanction_label(s), s.reason]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp notified_text(date, today) do
    case Date.diff(today, date) do
      0 -> gettext("parents notifiés aujourd'hui")
      1 -> gettext("parents notifiés hier")
      _ -> gettext("parents notifiés le %{date}", date: Dates.short(date))
    end
  end
end
