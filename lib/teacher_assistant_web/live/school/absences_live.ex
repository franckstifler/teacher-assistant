defmodule TeacherAssistantWeb.School.AbsencesLive do
  @moduledoc """
  Surveillant général → Absences (spec G, V02/V04): one row per student-day of
  the current séquence with an absence, filterable by justification, with a side
  panel to justify the day and the repeated-absence warning.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.School.SchoolLifeComponents

  alias TeacherAssistant.{Attendance, Discipline}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.{Authz, Dates}

  @filters ~w(unjustified justified all)

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Discipline.can_manage_conduct?(scope) do
      {:ok, socket |> assign(filter: "unjustified", selected: nil) |> load()}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    filter = if params["filter"] in @filters, do: params["filter"], else: "unjustified"
    {:noreply, assign(socket, filter: filter)}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    today = Reference.today()

    rows =
      case Attendance.current_sequence_range(scope, today) do
        nil -> []
        {first, last} -> Attendance.absence_days(scope, first, last, today)
      end

    selected = socket.assigns.selected && Enum.find(rows, &(&1.id == socket.assigns.selected.id))
    assign(socket, today: today, rows: rows, selected: selected)
  end

  def handle_event("select", %{"row" => row_id}, socket),
    do: {:noreply, assign(socket, selected: Enum.find(socket.assigns.rows, &(&1.id == row_id)))}

  def handle_event("justify", %{"row" => row_id, "reason" => reason}, socket) do
    case justify(socket.assigns.current_scope, socket.assigns.rows, row_id, reason) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  defp visible(rows, "unjustified"), do: Enum.reject(rows, & &1.justified?)
  defp visible(rows, "justified"), do: Enum.filter(rows, & &1.justified?)
  defp visible(rows, _all), do: rows

  defp filter_label("unjustified"), do: gettext("Non justifiées")
  defp filter_label("justified"), do: gettext("Justifiées")
  defp filter_label("all"), do: gettext("Toutes")

  def render(assigns) do
    shown = visible(assigns.rows, assigns.filter)

    # As in the mockup, the panel shows the chosen row, else the first one listed.
    selected =
      (assigns.selected && Enum.find(shown, &(&1.id == assigns.selected.id))) || List.first(shown)

    assigns = assign(assigns, filters: @filters, shown: shown, selected: selected)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="absences" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Absences")}>
          <:actions>
            <.side_chip id="unjustified-count">
              {ngettext(
                "%{count} non justifiée",
                "%{count} non justifiées",
                Enum.count(@rows, &(not &1.justified?))
              )}
            </.side_chip>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap items-start gap-4">
          <div class="flex min-w-0 flex-[1_1_560px] flex-col overflow-hidden rounded-box border border-base-300 bg-base-100">
            <div class="flex flex-wrap items-center gap-1.5 border-b border-base-300 px-3.5 py-3">
              <.link
                :for={f <- @filters}
                id={"filter-#{f}"}
                patch={~p"/school/absences?filter=#{f}"}
                aria-current={@filter == f && "page"}
                class={[
                  "rounded-full border px-3 py-1.5 text-[0.78rem] font-semibold transition-colors",
                  if(@filter == f,
                    do: "border-primary bg-primary/20 text-primary",
                    else: "border-base-300 hover:border-primary/60"
                  )
                ]}
              >
                {filter_label(f)}
              </.link>
            </div>
            <div class="overflow-x-auto">
              <div id="absence-rows" class="min-w-[700px]">
                <div class={[row_grid(), "border-b border-base-300 py-2.5"]}>
                  <span
                    :for={
                      label <- [
                        gettext("Date"),
                        gettext("Élève"),
                        gettext("Classe"),
                        gettext("Créneaux"),
                        gettext("Statut")
                      ]
                    }
                    class="ta-num text-[0.65rem] font-semibold uppercase tracking-[0.06em] text-base-content/75"
                  >
                    {label}
                  </span>
                </div>
                <button
                  :for={row <- @shown}
                  id={"row-#{row.id}"}
                  type="button"
                  phx-click="select"
                  phx-value-row={row.id}
                  aria-pressed={to_string(@selected != nil and @selected.id == row.id)}
                  class={[
                    row_grid(),
                    "ta-row-rule w-full cursor-pointer items-center py-[9px] text-left text-[0.86rem] transition-colors hover:bg-base-content/5",
                    @selected && @selected.id == row.id && "bg-primary/10"
                  ]}
                >
                  <span class="ta-num truncate text-base-content/75">{Dates.relative(row.date, @today)}</span>
                  <span class="flex min-w-0 items-center gap-1.5 font-semibold">
                    <span class="truncate">{row.student.full_name}</span>
                    <span
                      :if={row.flagged?}
                      title={gettext("Absences répétées")}
                      class="ta-num flex-none rounded-full bg-error/20 px-1.5 text-[0.62rem] text-error"
                    >
                      {gettext("rép.")}
                    </span>
                  </span>
                  <span class="truncate">{row.class_group.label}</span>
                  <span class="truncate text-base-content/75">{periods_text(row.periods)}</span>
                  <span class={[
                    "truncate",
                    if(row.justified?, do: "text-primary", else: "text-warning")
                  ]}>
                    {if row.justified?, do: justified_label(row), else: gettext("Non justifiée")}
                    <.overdue_badge row={row} />
                  </span>
                </button>
              </div>
            </div>
            <p :if={@shown == []} id="no-absences" class="px-3.5 py-5 text-sm text-base-content/75">
              {gettext("Aucune absence pour ce filtre.")}
            </p>
          </div>

          <aside
            :if={@selected}
            id="absence-panel"
            class="ta-panel flex min-w-0 max-w-[420px] flex-[1_1_300px] flex-col gap-2.5 !border-primary !px-[18px] !py-4"
          >
            <div class="flex items-start justify-between gap-2">
              <span class="ta-num text-[0.66rem] font-semibold uppercase tracking-[0.12em] text-primary/90">
                {@selected.class_group.label} · {Dates.relative(@selected.date, @today)}
              </span>
              <span class="flex items-center gap-1.5">
                <.overdue_badge row={@selected} />
                <.absence_status row={@selected} />
              </span>
            </div>
            <span class="font-display text-[1.3rem] font-semibold leading-tight">
              {@selected.student.full_name}
            </span>
            <span :if={@selected.flagged?} class="self-start"><.repeated_badge row={@selected} /></span>
            <span class="text-[0.82rem] text-base-content/80">{periods_text(@selected.periods)}</span>
            <div class="flex justify-between gap-2.5 border-b border-base-300/60 py-1.5 text-[0.85rem]">
              <span class="text-base-content/80">
                {gettext("Absences non justifiées (séquence)")}
              </span>
              <span id="unjustified-hours" class="ta-num font-semibold">
                {hours_label(@selected.unjustified_hours)}
              </span>
            </div>
            <div :if={not @selected.justified?} class="flex flex-col gap-1.5">
              <span class="text-[0.8rem] font-semibold">{gettext("Motif de justification")}</span>
              <.reason_chips row={@selected} />
            </div>
            <p
              :if={@selected.flagged?}
              id="repeated-warning"
              class="rounded-[0.4rem] border border-dashed border-warning/60 px-3 py-2 text-[0.82rem] text-warning"
            >
              {gettext("Absences répétées : convocation des parents recommandée.")}
            </p>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp hours_label(%Decimal{} = hours),
    do: "#{hours |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)} h"

  defp row_grid,
    do: "grid grid-cols-[110px_minmax(170px,1.4fr)_70px_minmax(0,1fr)_150px] gap-2.5 px-3.5"
end
