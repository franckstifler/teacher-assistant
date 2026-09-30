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
  alias TeacherAssistantWeb.{Authz, SanctionLabels}

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

    assign(socket,
      today: today,
      day: Attendance.school_day(scope, today, Reference.now()),
      absences: Attendance.absence_days(scope, today, today, today),
      sanctions: Discipline.recent_sanctions!(scope: scope)
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
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-day" class="flex flex-col gap-6">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Aujourd'hui")}>
          <:actions>
            <span class="ta-num inline-flex items-center rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold text-base-content/70">
              {Calendar.strftime(@today, "%d/%m/%Y")}
            </span>
          </:actions>
        </.page_header>

        <div :if={@day.rows == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={gettext("Pas de cours aujourd'hui")} />
        </div>

        <div :if={@day.rows != []} class="ta-leaf flex flex-col gap-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="ta-eyebrow">{gettext("Appels du jour")}</h2>
            <div class="flex gap-3 text-xs text-base-content/70">
              <span class="flex items-center gap-1">
                <span class="size-2.5 rounded-sm bg-success"></span>{gettext("Fait")}
              </span>
              <span class="flex items-center gap-1">
                <span class="size-2.5 rounded-sm bg-warning"></span>{gettext("Non fait")}
              </span>
              <span class="flex items-center gap-1">
                <span class="size-2.5 rounded-sm bg-info"></span>{gettext("En cours")}
              </span>
            </div>
          </div>
          <div class="overflow-x-auto">
            <table id="roll-call-grid" class="table table-xs">
              <thead>
                <tr>
                  <th>{gettext("Classe")}</th>
                  <th :for={p <- @day.periods} class="ta-num text-center" title={hm(p.start_time)}>
                    {p.label}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @day.rows} id={"grid-#{row.class_group.id}"}>
                  <th class="whitespace-nowrap">{row.class_group.label}</th>
                  <td :for={p <- @day.periods} class="text-center">
                    <.grid_cell cell={row.cells[p.id]} />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <div id="absences-to-justify" class="flex flex-col gap-2">
            <h2 class="ta-eyebrow">{gettext("Absences à justifier")}</h2>
            <p :if={@absences == []} class="text-sm text-base-content/60">
              {gettext("Aucune absence aujourd'hui.")}
            </p>
            <div :for={row <- @absences} id={"absence-#{row.id}"} class="ta-leaf flex flex-col gap-2">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="min-w-0">
                  <p class="font-semibold">
                    {row.student.full_name} <.repeated_badge row={row} />
                  </p>
                  <p class="text-xs text-base-content/70">
                    {row.class_group.label} · {periods_text(row.periods)}
                  </p>
                </div>
                <.absence_status :if={row.justified?} row={row} />
                <button
                  :if={not row.justified?}
                  id={"open-#{row.id}"}
                  type="button"
                  class="btn btn-primary btn-xs"
                  phx-click="open"
                  phx-value-row={row.id}
                >
                  {gettext("Justifier")}
                </button>
              </div>
              <.reason_chips :if={@open == row.id} row={row} />
            </div>
          </div>

          <div class="flex flex-col gap-6">
            <div id="missed-roll-calls" class="flex flex-col gap-2">
              <h2 class="ta-eyebrow">{gettext("Appels non faits")}</h2>
              <p :if={@day.missed == []} class="text-sm text-base-content/60">
                {gettext("Tous les appels passés sont faits.")}
              </p>
              <div
                :for={m <- @day.missed}
                id={"missed-#{m.class_group.id}-#{m.period.id}"}
                class="ta-leaf text-sm"
              >
                <p class="font-semibold">
                  {m.class_group.label} · {m.period.label} {hm(m.period.start_time)}
                </p>
                <p class="text-xs text-base-content/70">{teacher_name(m.teacher)} · {m.subject}</p>
              </div>
            </div>

            <div id="recent-sanctions" class="flex flex-col gap-2">
              <h2 class="ta-eyebrow">{gettext("Sanctions récentes")}</h2>
              <p :if={@sanctions == []} class="text-sm text-base-content/60">
                {gettext("Aucune sanction")}
              </p>
              <.link
                :for={s <- @sanctions}
                id={"sanction-#{s.id}"}
                navigate={~p"/school/classes/#{s.enrollment.class_group_id}/discipline"}
                class="ta-leaf flex items-center justify-between gap-2 text-sm transition hover:border-primary/50"
              >
                <span class="min-w-0">
                  <span class="font-semibold">{s.enrollment.student.full_name}</span>
                  <span class="text-base-content/70">
                    · {s.enrollment.class_group.label} · {SanctionLabels.type_label(s.type)}
                  </span>
                </span>
                <span :if={s.parents_notified_on} class="text-xs text-base-content/60">
                  {gettext("notifiés le %{date}",
                    date: Calendar.strftime(s.parents_notified_on, "%d/%m")
                  )}
                </span>
                <span :if={is_nil(s.parents_notified_on)} class="badge badge-warning badge-sm">
                  {gettext("parents à notifier")}
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

  defp grid_cell(%{cell: nil} = assigns), do: ~H""

  defp grid_cell(assigns) do
    ~H"""
    <span
      title={"#{@cell.subject} · #{teacher_name(@cell.teacher)} · #{hm(@cell.period.start_time)}–#{hm(@cell.period.end_time)}"}
      class={[
        "ta-num inline-grid min-w-7 place-items-center rounded px-1 py-0.5 text-xs font-semibold",
        @cell.status == :done && "bg-success/20 text-success",
        @cell.status == :missed && "bg-warning/20 text-warning",
        @cell.status == :in_progress && "bg-info/20 text-info",
        @cell.status == :upcoming && "text-base-content/40"
      ]}
    >
      {cell_text(@cell)}
    </span>
    """
  end

  defp cell_text(%{status: :done, absent: n}), do: n
  defp cell_text(%{status: :missed}), do: "—"
  defp cell_text(%{status: :in_progress}), do: "…"
  defp cell_text(%{status: :upcoming}), do: "·"
end
