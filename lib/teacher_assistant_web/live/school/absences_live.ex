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
  alias TeacherAssistantWeb.Authz

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
    assign(socket, rows: rows, selected: selected)
  end

  def handle_event("select", %{"row" => row_id}, socket),
    do: {:noreply, assign(socket, selected: Enum.find(socket.assigns.rows, &(&1.id == row_id)))}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, selected: nil)}

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
    assigns = assign(assigns, filters: @filters, shown: visible(assigns.rows, assigns.filter))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="absences" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Absences")}>
          <:actions>
            <div role="tablist" class="tabs tabs-box tabs-sm">
              <.link
                :for={f <- @filters}
                id={"filter-#{f}"}
                role="tab"
                patch={~p"/school/absences?filter=#{f}"}
                class={["tab", @filter == f && "tab-active"]}
              >
                {filter_label(f)}
              </.link>
            </div>
          </:actions>
        </.page_header>

        <div class="grid gap-5 lg:grid-cols-[1fr_20rem]">
          <div class="ta-leaf overflow-x-auto p-0">
            <table id="absence-rows" class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Date")}</th>
                  <th>{gettext("Élève")}</th>
                  <th>{gettext("Classe")}</th>
                  <th>{gettext("Créneaux")}</th>
                  <th>{gettext("Statut")}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @shown}
                  id={"row-#{row.id}"}
                  phx-click="select"
                  phx-value-row={row.id}
                  class={[
                    "cursor-pointer transition hover:bg-base-200",
                    @selected && @selected.id == row.id && "bg-primary/10"
                  ]}
                >
                  <td class="ta-num">{Calendar.strftime(row.date, "%d/%m")}</td>
                  <td>{row.student.full_name} <.repeated_badge row={row} /></td>
                  <td>{row.class_group.label}</td>
                  <td class="ta-num">{Enum.map_join(row.periods, ", ", & &1.label)}</td>
                  <td><.absence_status row={row} /></td>
                </tr>
              </tbody>
            </table>
            <p :if={@shown == []} id="no-absences" class="p-4 text-sm text-base-content/60">
              {gettext("Aucune absence pour ce filtre.")}
            </p>
          </div>

          <aside :if={@selected} id="absence-panel" class="ta-leaf flex flex-col gap-3 text-sm">
            <div class="flex items-start justify-between gap-2">
              <div>
                <p class="font-semibold">{@selected.student.full_name}</p>
                <p class="text-base-content/70">
                  {@selected.class_group.label} · {Calendar.strftime(@selected.date, "%d/%m/%Y")}
                </p>
              </div>
              <button type="button" class="btn btn-ghost btn-xs" phx-click="close">
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <p>{periods_text(@selected.periods)}</p>
            <.absence_status row={@selected} />
            <p>
              {gettext("Absences non justifiées : %{count} jour(s) dans la séquence",
                count: @selected.unjustified_days
              )}
            </p>
            <.reason_chips :if={not @selected.justified?} row={@selected} />
            <p :if={@selected.flagged?} id="repeated-warning" class="text-error">
              {gettext("Absences répétées : convocation des parents recommandée.")}
            </p>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
