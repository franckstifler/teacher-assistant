defmodule TeacherAssistantWeb.School.ResultsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []

      {:ok,
       socket
       |> assign(cg: cg, form_master: Academics.form_master(cg), sequences: sequences)
       |> select_seq(nil)}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket), do: {:noreply, select_seq(socket, params["seq"])}

  def handle_event("select_seq", %{"seq" => seq_id}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/school/classes/#{socket.assigns.cg.id}/results?seq=#{seq_id}")}
  end

  defp select_seq(socket, seq_id) do
    seq =
      Enum.find(socket.assigns.sequences, &(&1.id == seq_id)) ||
        List.first(socket.assigns.sequences)

    results = if seq, do: Academics.class_results(socket.assigns.cg, seq)
    roster = Academics.list_roster(socket.assigns.cg)
    assign(socket, seq: seq, results: results, roster: roster, rows: ranked_rows(results, roster))
  end

  # Build the display rows sorted by rank (unranked/ungraded last, by name).
  defp ranked_rows(nil, _roster), do: []

  defp ranked_rows(results, roster) do
    by_student = Map.new(roster, fn %{student: s, enrollment: e} -> {s.id, {s, e}} end)

    results.per_student
    |> Enum.flat_map(fn {student_id, data} ->
      case Map.get(by_student, student_id) do
        {student, enrollment} -> [%{student: student, enrollment: enrollment, data: data}]
        nil -> []
      end
    end)
    |> Enum.sort_by(fn %{student: s, data: d} ->
      {d.rank || 9_999, String.downcase(s.full_name)}
    end)
  end

  defp names(ids, roster) do
    by_id = Map.new(roster, fn %{student: s} -> {s.id, s.full_name} end)
    ids |> Enum.map(&Map.get(by_id, &1)) |> Enum.reject(&is_nil/1)
  end

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()
  defp pct(rate), do: "#{round(rate * 100)}%"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-results" class="space-y-6">
        <.page_header
          eyebrow={gettext("Conseil de classe")}
          title={"#{@cg.label} — #{gettext("Résultats & bulletins")}"}
        >
          <:actions>
            <form :if={@sequences != []} id="results-seq-form" phx-change="select_seq">
              <.input
                type="select"
                id="results-seq-select"
                name="seq"
                value={@seq && @seq.id}
                options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
              />
            </form>
          </:actions>
        </.page_header>

        <p :if={@form_master} class="text-sm text-base-content/70">
          {gettext("Professeur principal")}: {@form_master.email}
        </p>

        <.empty_state
          :if={@seq == nil}
          icon="hero-calendar-days"
          title={gettext("Aucune séquence")}
          message={gettext("Create an academic year and its calendar first.")}
        />

        <.empty_state
          :if={@seq != nil and @results == nil}
          icon="hero-academic-cap"
          title={gettext("Aucun enseignant affecté")}
          message={gettext("Assign subjects to this class to compute bulletins.")}
        />

        <div :if={@results} class="space-y-6">
          <div id="results-stats" class="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <.stat
              label={gettext("Moyenne de la classe")}
              value={fmt(@results.class_average)}
              suffix="/20"
              tone={:primary}
            />
            <.stat label={gettext("Taux de réussite")} value={pct(@results.pass_rate)} />
            <.stat label={gettext("Plus forte moyenne")} value={fmt(@results.highest)} suffix="/20" />
            <.stat label={gettext("Plus faible moyenne")} value={fmt(@results.lowest)} suffix="/20" />
          </div>

          <div class="grid grid-cols-2 gap-2 text-sm sm:grid-cols-3">
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Effectif")}</p>
              <p class="ta-num">{@results.effectif}</p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Filles")}</p>
              <p class="ta-num">
                {fmt(@results.by_sex.f.class_average)} · {pct(@results.by_sex.f.pass_rate)}
              </p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Garçons")}</p>
              <p class="ta-num">
                {fmt(@results.by_sex.m.class_average)} · {pct(@results.by_sex.m.pass_rate)}
              </p>
            </div>
          </div>

          <div id="results-distinctions" class="space-y-1 text-sm">
            <p :if={@results.distinctions.felicitations != []}>
              <span class="badge badge-success">{gettext("Félicitations")}</span>
              {Enum.join(names(@results.distinctions.felicitations, @roster), ", ")}
            </p>
            <p :if={@results.distinctions.encouragements != []}>
              <span class="badge badge-info">{gettext("Encouragements")}</span>
              {Enum.join(names(@results.distinctions.encouragements, @roster), ", ")}
            </p>
            <p :if={@results.distinctions.tableau_honneur != []}>
              <span class="badge badge-ghost">{gettext("Tableau d'honneur")}</span>
              {Enum.join(names(@results.distinctions.tableau_honneur, @roster), ", ")}
            </p>
          </div>

          <div class="overflow-x-auto">
            <table id="results-table" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Rang")}</th>
                  <th>{gettext("Nom et prénoms")}</th>
                  <th>{gettext("Moyenne générale")}</th>
                  <th>{gettext("Mention")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @rows} id={"results-row-#{row.student.id}"}>
                  <td class="ta-num">{row.data.rank || "—"}</td>
                  <td>
                    <.link
                      navigate={
                        ~p"/school/classes/#{@cg.id}/students/#{row.enrollment.id}/bulletin?seq=#{@seq.id}"
                      }
                      class="link"
                    >
                      {row.student.full_name}
                    </.link>
                  </td>
                  <td class="ta-num">{fmt(row.data.moyenne_generale)}</td>
                  <td><.mention_badge :if={row.data.mention} mention={row.data.mention} /></td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="flex justify-end">
            <a
              id="print-whole-class"
              href={~p"/school/classes/#{@cg.id}/bulletin/print?seq=#{@seq.id}"}
              target="_blank"
              class="btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-printer" class="size-4" />
              {gettext("Imprimer toute la classe")}
            </a>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
