defmodule TeacherAssistantWeb.School.ResultsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.ReportCards

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         access when access != :none <- ReportCards.access(scope, cg) do
      year = Organization.class_year(scope, cg)
      sequences = if year, do: Organization.list_sequences(scope, year), else: []
      terms = if year, do: Organization.list_terms(scope, year), else: []

      {:ok,
       socket
       |> assign(
         cg: cg,
         form_master: Enrollment.form_master(scope, cg),
         year: year,
         sequences: sequences,
         terms: terms
       )
       |> select_period(nil)}
    else
      :none -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, select_period(socket, params["period"])}

  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/school/classes/#{socket.assigns.cg.id}/results?period=#{param}")}
  end

  defp select_period(socket, param) do
    year = socket.assigns.year

    period =
      (year && param && Organization.resolve_period(socket.assigns.current_scope, year, param)) ||
        default_period(socket.assigns.sequences)

    {status, publication, view} =
      case period && ReportCards.view_for(socket.assigns.current_scope, socket.assigns.cg, period) do
        {:published, pub, view} -> {:published, pub, view}
        {:draft, view} -> {:draft, nil, view}
        _ -> {:not_published, nil, nil}
      end

    results = view && view.results
    roster = (view && view.roster) || []

    assign(socket,
      period: period,
      period_param: period && Organization.period_param(period),
      status: if(period, do: status, else: :draft),
      publication: publication,
      results: results,
      roster: roster,
      rows: ranked_rows(results, roster)
    )
  end

  defp default_period([]), do: nil
  defp default_period([seq | _]), do: {:sequence, seq}

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
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="class-results" class="space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Résultats & bulletins")}"}
        >
          <:actions>
            <form :if={@sequences != []} id="results-period-form" phx-change="select_period">
              <.input
                type="select"
                id="results-period-select"
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
          </:actions>
        </.page_header>

        <p
          :if={@year && @year.status == :closed}
          id="year-closed"
          class="badge badge-ghost gap-1 self-start"
        >
          <.icon name="hero-lock-closed" class="size-3.5" />
          {gettext("Année %{name} · clôturée", name: @year.name)}
        </p>

        <p :if={@form_master} class="text-sm text-base-content/70">
          {gettext("Professeur principal")}: {User.display_name(@form_master)}
        </p>

        <.empty_state
          :if={@period == nil}
          icon="hero-calendar-days"
          title={gettext("Aucune séquence")}
          message={gettext("Create an academic year and its calendar first.")}
        />

        <p :if={@status == :published} id="results-published" class="badge badge-success gap-1">
          <.icon name="hero-check-badge" class="size-4" />
          {gettext("Publié le %{date}",
            date: Calendar.strftime(ReportCards.published_on(@publication), "%d/%m/%Y")
          )}
        </p>

        <div :if={@status == :not_published} id="results-not-published">
          <.empty_state
            icon="hero-lock-closed"
            title={gettext("Pas encore publiés")}
            message={gettext("Les bulletins de cette période n'ont pas encore été publiés.")}
          />
        </div>

        <.empty_state
          :if={@period != nil and @status != :not_published and @results == nil}
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

          <p
            :if={@results.makeup_pending_count > 0}
            id="results-makeups"
            class="alert alert-warning text-sm"
          >
            {gettext("Rattrapages attendus : %{count}", count: @results.makeup_pending_count)}
          </p>

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
            <p
              :for={kind <- TeacherAssistant.Academics.Distinction.values()}
              :if={@results.distinctions[kind] != []}
              id={"distinction-#{kind}"}
            >
              <.distinction_badge distinction={kind} />
              {Enum.join(names(@results.distinctions[kind], @roster), ", ")}
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
                        ~p"/school/classes/#{@cg.id}/students/#{row.enrollment.id}/bulletin?period=#{@period_param}"
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
              href={~p"/school/classes/#{@cg.id}/bulletin/print?period=#{@period_param}"}
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
