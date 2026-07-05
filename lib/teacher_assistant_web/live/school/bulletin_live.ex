defmodule TeacherAssistantWeb.School.BulletinLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id, "enrollment_id" => eid} = params, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.admin?(scope),
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         roster = Academics.list_roster(cg),
         %{student: student, enrollment: enrollment} <-
           Enum.find(roster, &(&1.enrollment.id == eid)) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []

      seq =
        Enum.find(sequences, &(&1.id == params["seq"])) || List.first(sequences)

      results = if seq, do: Academics.class_results(cg, seq)
      data = results && results.per_student[student.id]

      {:ok,
       assign(socket,
         cg: cg,
         student: student,
         enrollment: enrollment,
         seq: seq,
         effectif: (results && results.effectif) || 0,
         data: data
       )}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}/results")}
    end
  end

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp sex_label(:f), do: gettext("Féminin")
  defp sex_label(_), do: gettext("Masculin")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="bulletin" class="mx-auto max-w-3xl space-y-6">
        <.page_header eyebrow={gettext("Bulletin de notes")} title={@student.full_name}>
          <:actions>
            <a
              :if={@seq}
              id="bulletin-print"
              href={
                ~p"/school/classes/#{@cg.id}/students/#{@enrollment.id}/bulletin/print?seq=#{@seq.id}"
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
            <dt class="ta-eyebrow">{gettext("Séquence")}</dt>
            <dd>{@seq && "#{gettext("Séquence")} #{@seq.number}"}</dd>
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
          subtitle={gettext("No marks for this séquence yet.")}
        />

        <div :if={@data} class="space-y-4">
          <div class="overflow-x-auto">
            <table id="bulletin-subjects" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Matière")}</th>
                  <th>{gettext("Coefficient")}</th>
                  <th>{gettext("Note")}/20</th>
                  <th>{gettext("Note×Coef")}</th>
                  <th>{gettext("Cote classe")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @data.subjects} id={"bulletin-subject-#{row.context_id}"}>
                  <td>{row.label}</td>
                  <td class="ta-num">{fmt(row.coefficient)}</td>
                  <td class="ta-num">{fmt(row.average)}</td>
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
      </section>
    </Layouts.app>
    """
  end
end
