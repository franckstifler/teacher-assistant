defmodule TeacherAssistantWeb.School.DayLive do
  @moduledoc """
  Surveillant général → Aujourd'hui (spec G, V01–V04, V06): today's roll calls
  as a classes × periods grid, the absences to justify, the missed roll calls
  and the school's latest sanctions. The surveillant space's home.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.School.SchoolLifeComponents

  alias TeacherAssistant.{Attendance, Discipline}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.{Authz, Dates, SanctionLabels}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Discipline.can_manage_conduct?(scope) do
      {:ok, socket |> assign(open: nil) |> load()}
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

    assign(socket,
      today: today,
      now: now,
      day: Attendance.school_day(scope, today, now),
      absences: Attendance.absence_days(scope, today, today, today),
      sanctions: Discipline.recent_sanctions!(scope: scope),
      to_notify: length(Discipline.list_parents_to_notify!(scope: scope))
    )
  end

  def handle_event("open", %{"row" => row_id}, socket),
    do: {:noreply, assign(socket, open: if(socket.assigns.open == row_id, do: nil, else: row_id))}

  def handle_event("justify", %{"row" => row_id, "reason" => reason}, socket) do
    case justify(socket.assigns.current_scope, socket.assigns.absences, row_id, reason) do
      {:ok, _} -> {:noreply, socket |> assign(open: nil) |> load()}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        current: current_period(assigns.day.periods, assigns.now),
        open_rows: Enum.reject(assigns.absences, & &1.justified?)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-day" class="flex flex-col gap-5">
        <.page_header
          eyebrow={
            gettext("Vie scolaire · %{date} · %{time}",
              date: Dates.long(@today),
              time: Calendar.strftime(@now, "%H:%M")
            )
          }
          title={gettext("Aujourd'hui")}
        >
          <:actions :if={@current}>
            <.side_chip id="current-period">
              {gettext("Créneau en cours · %{period}", period: @current.label)}
            </.side_chip>
          </:actions>
        </.page_header>

        <.kpi_row>
          <.kpi
            id="kpi-absences"
            label={gettext("Absences du jour")}
            value={to_string(absent_total(@day))}
            sub={done_range(@day)}
          />
          <.kpi
            id="kpi-to-justify"
            label={gettext("À justifier")}
            value={to_string(length(@open_rows))}
            sub={
              ngettext(
                "dont %{count} absence répétée",
                "dont %{count} absences répétées",
                Enum.count(@open_rows, & &1.flagged?)
              )
            }
            tone="text-warning"
          />
          <.kpi
            id="kpi-missed"
            label={gettext("Appels non faits")}
            value={to_string(length(@day.missed))}
            sub={gettext("créneaux déjà passés")}
            tone="text-error"
          />
          <.kpi
            id="kpi-to-notify"
            label={gettext("Sanctions à notifier")}
            value={to_string(@to_notify)}
            sub={gettext("aux parents")}
          />
        </.kpi_row>

        <div :if={@day.rows == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={gettext("Pas de cours aujourd'hui")} />
        </div>

        <div :if={@day.rows != []} class="ta-panel flex flex-col gap-2.5 overflow-x-auto">
          <div class="flex flex-wrap items-center justify-between gap-3.5">
            <h2 class="ta-eyebrow">{gettext("Appels par créneau · nombre d'absents")}</h2>
            <div class="flex gap-3 text-[0.74rem] text-base-content/80">
              <span class="flex items-center gap-[5px]">
                <i class="size-2.5 rounded-[3px] bg-primary/45"></i>{gettext("Fait")}
              </span>
              <span class="flex items-center gap-[5px]">
                <i class="size-2.5 rounded-[3px] bg-error/60"></i>{gettext("Non fait")}
              </span>
              <span class="flex items-center gap-[5px]">
                <i class="size-2.5 rounded-[3px] border border-warning"></i>{gettext("En cours")}
              </span>
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
          <div id="absences-to-justify" class="ta-panel flex flex-col gap-0.5">
            <div class="flex items-baseline justify-between gap-2">
              <h2 class="ta-eyebrow">{gettext("Absences à justifier")}</h2>
              <span class="ta-num text-[0.75rem] text-warning">
                {ngettext("%{count} en attente", "%{count} en attente", length(@open_rows))}
              </span>
            </div>
            <p :if={@absences == []} class="py-2 text-sm text-base-content/70">
              {gettext("Aucune absence aujourd'hui.")}
            </p>
            <div
              :for={row <- @absences}
              id={"absence-#{row.id}"}
              class="ta-row-rule flex flex-col gap-2 py-2"
            >
              <div class="flex items-center gap-2.5">
                <div class="flex min-w-0 flex-1 flex-col">
                  <span class="flex flex-wrap items-center gap-1.5 text-[0.9rem] font-semibold">
                    {row.student.full_name} <.repeated_badge row={row} />
                  </span>
                  <span class="text-[0.75rem] text-base-content/75">
                    {row.class_group.label} · {periods_text(row.periods)}
                  </span>
                </div>
                <.absence_status :if={row.justified?} row={row} />
                <button
                  :if={not row.justified?}
                  id={"open-#{row.id}"}
                  type="button"
                  class="flex-none cursor-pointer rounded-[0.35rem] border border-base-300 px-[11px] py-[7px] text-[0.76rem] font-semibold transition-colors hover:border-primary hover:text-primary"
                  phx-click="open"
                  phx-value-row={row.id}
                >
                  {gettext("Justifier")}
                </button>
              </div>
              <.reason_chips :if={@open == row.id} row={row} />
            </div>
          </div>

          <div class="flex flex-col gap-4">
            <div id="missed-roll-calls" class="ta-panel flex flex-col gap-0.5">
              <div class="flex items-baseline justify-between gap-2">
                <h2 class="ta-eyebrow">{gettext("Appels non faits")}</h2>
                <span class="ta-num text-[0.75rem] text-error">{length(@day.missed)}</span>
              </div>
              <p :if={@day.missed == []} class="py-2 text-sm text-base-content/70">
                {gettext("Tous les appels passés sont faits.")}
              </p>
              <div
                :for={m <- @day.missed}
                id={"missed-#{m.class_group.id}-#{m.period.id}"}
                class="ta-row-rule flex flex-col py-[7px]"
              >
                <span class="ta-num text-[0.88rem] font-semibold">
                  {m.class_group.label} · {m.period.label} {hm(m.period.start_time)}
                </span>
                <span class="text-[0.74rem] text-base-content/75">
                  {teacher_name(m.teacher)} · {m.subject}
                </span>
              </div>
            </div>

            <div id="recent-sanctions" class="ta-panel flex flex-col gap-0.5">
              <h2 class="ta-eyebrow pb-1">{gettext("Sanctions récentes")}</h2>
              <p :if={@sanctions == []} class="py-2 text-sm text-base-content/70">
                {gettext("Aucune sanction")}
              </p>
              <.link
                :for={s <- @sanctions}
                id={"sanction-#{s.id}"}
                navigate={~p"/school/classes/#{s.enrollment.class_group_id}/discipline"}
                class="ta-row-rule flex flex-col gap-0.5 py-[7px] transition-colors hover:text-primary"
              >
                <span class="text-[0.88rem] font-semibold">
                  {s.enrollment.student.full_name} · {s.enrollment.class_group.label}
                </span>
                <span class="text-[0.75rem] text-base-content/75">
                  {sanction_text(s)} ·
                  <b :if={is_nil(s.parents_notified_on)} class="text-warning">
                    {gettext("parents à notifier")}
                  </b>
                  <span :if={s.parents_notified_on}>{notified_text(s.parents_notified_on, @today)}</span>
                </span>
              </.link>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :cell, :map, default: nil

  defp grid_cell(%{cell: nil} = assigns), do: ~H|<span class="h-[30px]"></span>|

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

  defp cell_class(%{status: :done, absent: 0}), do: "border-transparent bg-primary/34"
  defp cell_class(%{status: :done}), do: "border-transparent bg-primary/22"
  defp cell_class(%{status: :missed}), do: "border-transparent bg-error/42"
  defp cell_class(%{status: :in_progress}), do: "border-warning text-warning"
  defp cell_class(%{status: :upcoming}), do: "border-dashed border-base-300 text-base-content/70"

  defp cell_text(%{status: :done, absent: n}), do: n
  defp cell_text(%{status: :missed}), do: "—"
  defp cell_text(%{status: :in_progress}), do: "…"
  defp cell_text(%{status: :upcoming}), do: "·"

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

  defp absent_total(day),
    do:
      for(
        row <- day.rows,
        {_id, %{status: :done, absent: n}} <- row.cells,
        reduce: 0,
        do: (acc -> acc + n)
      )

  # "créneaux Cours 1 à Cours 5": the span of periods whose roll call is done somewhere.
  defp done_range(day) do
    done_ids =
      for row <- day.rows, {id, %{status: :done}} <- row.cells, into: MapSet.new(), do: id

    case Enum.filter(day.periods, &MapSet.member?(done_ids, &1.id)) do
      [] ->
        gettext("aucun appel fait")

      [only] ->
        gettext("créneau %{period}", period: only.label)

      [first | rest] ->
        gettext("créneaux %{first} à %{last}", first: first.label, last: List.last(rest).label)
    end
  end

  defp sanction_text(s) do
    [SanctionLabels.type_label(s.type), s.reason]
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
