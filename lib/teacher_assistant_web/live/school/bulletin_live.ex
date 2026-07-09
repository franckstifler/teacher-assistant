defmodule TeacherAssistantWeb.School.BulletinLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistantWeb.SanctionLabels

  def mount(%{"id" => id, "enrollment_id" => eid} = params, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg),
         roster = Academics.list_roster(cg),
         %{student: student, enrollment: enrollment} <-
           Enum.find(roster, &(&1.enrollment.id == eid)) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      terms = if year, do: Academics.list_terms(year), else: []

      period =
        (year && Academics.resolve_period(year, params["period"])) ||
          case sequences do
            [seq | _] -> {:sequence, seq}
            [] -> nil
          end

      results = period && Academics.class_results_for_period(cg, period)
      data = results && results.per_student[student.id]
      conduct = period && Attendance.student_conduct(enrollment, period)
      discipline = period && Discipline.discipline_summary(enrollment, period)

      {:ok,
       assign(socket,
         cg: cg,
         student: student,
         enrollment: enrollment,
         year: year,
         sequences: sequences,
         terms: terms,
         period: period,
         period_param: period && Academics.period_param(period),
         period_kind: period && Academics.period_kind(period),
         effectif: (results && results.effectif) || 0,
         data: data,
         conduct: conduct,
         discipline: discipline
       )}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      nil -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}/results")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/school/classes/#{socket.assigns.cg.id}/students/#{socket.assigns.enrollment.id}/bulletin?period=#{param}"
     )}
  end

  def handle_params(%{"period" => _} = params, _uri, socket) do
    year = socket.assigns.year

    period =
      (year && Academics.resolve_period(year, params["period"])) || socket.assigns.period

    results = period && Academics.class_results_for_period(socket.assigns.cg, period)
    conduct = period && Attendance.student_conduct(socket.assigns.enrollment, period)
    discipline = period && Discipline.discipline_summary(socket.assigns.enrollment, period)

    {:noreply,
     assign(socket,
       period: period,
       period_param: period && Academics.period_param(period),
       period_kind: period && Academics.period_kind(period),
       effectif: (results && results.effectif) || 0,
       data: results && results.per_student[socket.assigns.student.id],
       conduct: conduct,
       discipline: discipline
     )}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp component_at(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end

  defp period_heading(%{period: {:sequence, seq}}), do: "#{gettext("Séquence")} #{seq.number}"

  defp period_heading(%{period: {:trimester, term}}),
    do: "#{gettext("Trimestre")} #{term.position}"

  defp period_heading(%{period: {:annual, _}}), do: gettext("Année scolaire")
  defp period_heading(_), do: "—"

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp sex_label(:f), do: gettext("Féminin")
  defp sex_label(_), do: gettext("Masculin")

  defp no_data_message(:trimester), do: gettext("No marks for this term yet.")
  defp no_data_message(:annual), do: gettext("No marks for this year yet.")
  defp no_data_message(_), do: gettext("No marks for this séquence yet.")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="bulletin" class="mx-auto max-w-3xl space-y-6">
        <.page_header eyebrow={gettext("Bulletin de notes")} title={@student.full_name}>
          <:actions>
            <form
              :if={@sequences != []}
              id="bulletin-period-form"
              phx-change="select_period"
              class="inline"
            >
              <.input
                type="select"
                id="bulletin-period-select"
                name="period"
                value={@period_param}
                options={[
                  {gettext("Séquences"),
                   for(s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", "seq:#{s.id}"})},
                  {gettext("Trimestres"),
                   for(t <- @terms, do: {gettext("Trimestre") <> " #{t.position}", "trim:#{t.id}"})},
                  {gettext("Année"), [{gettext("Année scolaire"), "annee"}]}
                ]}
              />
            </form>
            <a
              :if={@period}
              id="bulletin-print"
              href={
                ~p"/school/classes/#{@cg.id}/students/#{@enrollment.id}/bulletin/print?period=#{@period_param}"
              }
              target="_blank"
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-printer" class="size-4" />
              {gettext("Imprimer")}
            </a>
          </:actions>
        </.page_header>

        <dl id="bulletin-identity" class="grid grid-cols-2 gap-2 text-sm sm:grid-cols-3">
          <div>
            <dt class="ta-eyebrow">{gettext("Matricule")}</dt>
            <dd>{@student.matricule || "—"}</dd>
          </div>
          <div>
            <dt class="ta-eyebrow">{gettext("Classe")}</dt>
            <dd>{@cg.label} — {@cg.level}</dd>
          </div>
          <div>
            <dt class="ta-eyebrow">{gettext("Période")}</dt>
            <dd>{period_heading(assigns)}</dd>
          </div>
          <div>
            <dt class="ta-eyebrow">{gettext("Sexe")}</dt>
            <dd>{sex_label(@student.sex)}</dd>
          </div>
          <div>
            <dt class="ta-eyebrow">{gettext("Effectif")}</dt>
            <dd>{@effectif}</dd>
          </div>
        </dl>

        <.empty_state
          :if={is_nil(@data)}
          icon="hero-document-text"
          title={gettext("Aucune donnée")}
          message={no_data_message(@period_kind)}
        />

        <div :if={@data} class="space-y-4">
          <div class="overflow-x-auto">
            <table id="bulletin-subjects" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Matière")}</th>
                  <th>{gettext("Coefficient")}</th>
                  <%= case @period_kind do %>
                    <% :trimester -> %>
                      <th>{gettext("Séq 1")}</th>
                      <th>{gettext("Séq 2")}</th>
                      <th>{gettext("Moy. trim.")}</th>
                    <% :annual -> %>
                      <th>{gettext("Trim 1")}</th>
                      <th>{gettext("Trim 2")}</th>
                      <th>{gettext("Trim 3")}</th>
                      <th>{gettext("Moy. ann.")}</th>
                    <% _ -> %>
                      <th>{gettext("Note")}/20</th>
                  <% end %>
                  <th>{gettext("Note×Coef")}</th>
                  <th>{gettext("Cote classe")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @data.subjects} id={"bulletin-subject-#{row.context_id}"}>
                  <td>{row.label}</td>
                  <td class="ta-num">{fmt(row.coefficient)}</td>
                  <%= case @period_kind do %>
                    <% :trimester -> %>
                      <td class="ta-num">{fmt(component_at(row, :sequences, 0))}</td>
                      <td class="ta-num">{fmt(component_at(row, :sequences, 1))}</td>
                      <td class="ta-num">{fmt(row.average)}</td>
                    <% :annual -> %>
                      <td class="ta-num">{fmt(component_at(row, :trimesters, 0))}</td>
                      <td class="ta-num">{fmt(component_at(row, :trimesters, 1))}</td>
                      <td class="ta-num">{fmt(component_at(row, :trimesters, 2))}</td>
                      <td class="ta-num">{fmt(row.average)}</td>
                    <% _ -> %>
                      <td class="ta-num">{fmt(row.average)}</td>
                  <% end %>
                  <td class="ta-num">{fmt(row.note_x_coef)}</td>
                  <td class="ta-num">{fmt(row.class_min)} – {fmt(row.class_max)}</td>
                </tr>
              </tbody>
              <tfoot>
                <tr>
                  <th>{gettext("Total des points")}</th>
                  <th class="ta-num">{fmt(@data.total_coef)}</th>
                  <th></th>
                  <th class="ta-num">{fmt(@data.total_points)}</th>
                  <th></th>
                </tr>
              </tfoot>
            </table>
          </div>

          <div id="bulletin-totals" class="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <.stat
              label={gettext("Moyenne générale")}
              value={fmt(@data.moyenne_generale)}
              suffix="/20"
              tone={:primary}
            />
            <.stat label={gettext("Rang")} value={"#{@data.rank || "—"} / #{@effectif}"} />
            <div class="ta-leaf flex items-center">
              <.mention_badge :if={@data.mention} mention={@data.mention} />
            </div>
          </div>
        </div>

        <div :if={@conduct} id="bulletin-conduct" class="space-y-2">
          <h2 class="ta-eyebrow">{gettext("Conduite")}</h2>
          <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <.stat
              label={gettext("Absences justifiées")}
              value={fmt(@conduct.justified_hours)}
              suffix={gettext("h")}
            />
            <.stat
              label={gettext("Absences non justifiées")}
              value={fmt(@conduct.unjustified_hours)}
              suffix={gettext("h")}
            />
            <.stat label={gettext("Retards")} value={to_string(@conduct.retards)} />
          </div>
          <div
            :if={@discipline}
            id="bulletin-discipline"
            class="grid grid-cols-2 gap-2 sm:grid-cols-3"
          >
            <.stat label={gettext("Consignes")} value={to_string(@discipline.consignes_count)} />
            <.stat
              label={gettext("Note de conduite")}
              value={fmt(@discipline.note_de_conduite)}
              suffix="/20"
            />
            <div class="ta-leaf">
              <dt class="ta-eyebrow">{gettext("Sanctions")}</dt>
              <dd id="bulletin-sanctions">{SanctionLabels.sanctions_line(@discipline.sanctions)}</dd>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
