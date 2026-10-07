defmodule TeacherAssistantWeb.School.CouncilLive do
  @moduledoc """
  One class's council for a trimester (spec I3) or the year (spec I4, with a passage
  column): the header (date, président, présents,
  observations générales), the class statistics, and a row per student — the I1
  proposal, the council's distinction choice, a conduct warning and an appreciation,
  each row saved on change. "Marquer le conseil tenu" (confirmation below complete
  entry), "Rouvrir"; everything read-only once the term is published.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Assessment, Councils, Enrollment, Organization, ReportCards}

  alias TeacherAssistant.Academics.{
    ConductWarning,
    CouncilDistinctionChoice,
    EntryProgress,
    PassageDecision,
    Reference
  }

  def mount(%{"class_id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- ReportCards.can_publish?(scope),
         %{} = year <- scope.current_academic_year,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         [_ | _] = terms <- Organization.list_terms(scope, year) do
      {:ok, assign(socket, year: year, cg: cg, terms: terms, saved: nil, confirm_hold?: false)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    %{terms: terms, year: year} = socket.assigns

    period =
      case params do
        %{"period" => "annee"} ->
          {:annual, year}

        _ ->
          {:trimester,
           Enum.find(terms, &(&1.id == params["term"])) ||
             Councils.default_term(terms, Reference.today())}
      end

    {:noreply, socket |> assign(period: period, saved: nil, confirm_hold?: false) |> load()}
  end

  defp load(socket) do
    %{current_scope: scope, cg: cg, period: period, year: year} = socket.assigns
    council = Councils.council(scope, cg, period)
    results = Assessment.class_results_for_period(scope, cg, period)
    decisions = Map.new(council.decisions, &{&1.student_id, &1})
    outcomes = passage_outcomes(scope, cg, period, council, results)

    rows =
      scope
      |> Enrollment.list_roster(cg)
      |> Enum.map(fn %{student: s} ->
        %{
          student: s,
          data: results && results.per_student[s.id],
          decision: decisions[s.id],
          outcome: outcomes[s.id]
        }
      end)
      |> Enum.sort_by(
        &{(&1.data && &1.data.rank) || 9_999, String.downcase(&1.student.full_name)}
      )

    assign(socket,
      council: council,
      results: results,
      rows: rows,
      rate: scope |> EntryProgress.class_rates(year, sequences(scope, period)) |> Map.get(cg.id),
      locked?: Councils.locked?(scope, cg, period)
    )
  end

  # Spec I4: the annual council shows the passage proposal next to each student.
  defp passage_outcomes(scope, cg, {:annual, _} = period, council, results) do
    passage = %{
      rules: Assessment.passage_rules(scope),
      students: Councils.passage_inputs(scope, cg, period)
    }

    Councils.outcomes(council, results, passage)
  end

  defp passage_outcomes(_scope, _cg, _period, _council, _results), do: %{}

  defp sequences(_scope, {:trimester, term}), do: term.sequences
  defp sequences(scope, {:annual, year}), do: Organization.list_sequences(scope, year)

  def handle_event("save_header", %{"council" => params}, socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    scope
    |> Councils.save_header(cg, period, params)
    |> after_write(socket, gettext("Conseil enregistré."))
  end

  def handle_event("decision", %{"student_id" => student_id} = params, socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    case Councils.set_decision(scope, cg, period, student_id, Map.get(params, "decision", %{})) do
      {:ok, _} -> {:noreply, socket |> load() |> assign(saved: student_id)}
      other -> after_write(other, socket, nil)
    end
  end

  def handle_event("hold", _params, %{assigns: %{rate: 100}} = socket), do: hold(socket)
  def handle_event("hold", _params, socket), do: {:noreply, assign(socket, confirm_hold?: true)}
  def handle_event("confirm_hold", _params, socket), do: hold(socket)

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, confirm_hold?: false)}

  def handle_event("reopen", _params, socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    scope
    |> Councils.reopen(cg, period)
    |> after_write(socket, gettext("Conseil rouvert."))
  end

  defp hold(socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    scope
    |> Councils.hold(cg, period)
    |> after_write(assign(socket, confirm_hold?: false), gettext("Conseil marqué tenu."))
  end

  defp after_write({:ok, _}, socket, message) do
    socket = load(socket)
    {:noreply, if(message, do: put_flash(socket, :info, message), else: socket)}
  end

  defp after_write({:error, :locked}, socket, _message) do
    {:noreply,
     socket |> load() |> put_flash(:error, gettext("Conseil verrouillé : bulletins publiés."))}
  end

  defp after_write({:error, %Ash.Error.Forbidden{}}, socket, _message),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, _}, socket, _message),
    do: {:noreply, put_flash(socket, :error, gettext("Non enregistré : vérifiez les champs."))}

  defp choice_options do
    [{gettext("Proposition"), ""}] ++
      Enum.map(CouncilDistinctionChoice.values(), &{CouncilDistinctionChoice.label(&1), &1})
  end

  defp passage_options do
    [{gettext("Proposition"), ""}] ++
      Enum.map(PassageDecision.values(), &{PassageDecision.label(&1), &1})
  end

  # The engine's proposal and its reason, shown even after the council chose otherwise.
  defp proposal_text(%{proposal: nil}), do: "—"

  defp proposal_text(%{proposal: proposal, proposal_reason: nil}),
    do: gettext("Proposition : %{decision}", decision: PassageDecision.label(proposal))

  defp proposal_text(%{proposal: proposal, proposal_reason: reason}),
    do:
      gettext("Proposition : %{decision} (%{reason})",
        decision: PassageDecision.label(proposal),
        reason: reason
      )

  defp proposal_text(_), do: "—"

  defp annual?({:annual, _}), do: true
  defp annual?(_), do: false

  defp period_title({:annual, _}), do: gettext("Conseil de fin d'année")

  defp period_title({:trimester, term}),
    do: gettext("Conseil de classe · Trimestre %{n}", n: term.position)

  defp period_params({:annual, _}), do: %{period: "annee"}
  defp period_params({:trimester, term}), do: %{term: term.id}

  defp grid_cols({:annual, _}),
    do: "lg:grid-cols-[3rem_minmax(0,1.4fr)_4rem_9rem_10rem_10rem_minmax(0,1.6fr)_11rem_4rem]"

  defp grid_cols(_),
    do: "lg:grid-cols-[3rem_minmax(0,1.4fr)_4rem_9rem_10rem_10rem_minmax(0,1.6fr)_4rem]"

  defp warning_options do
    [{gettext("Aucun"), ""}] ++
      Enum.map(ConductWarning.values(), &{ConductWarning.label(&1), &1})
  end

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp pct(nil), do: "—"
  defp pct(rate), do: "#{round(rate * 100)} %"

  defp rate_text(nil), do: "—"
  defp rate_text(rate), do: "#{rate} %"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="council" class="space-y-5">
        <.page_header
          eyebrow={period_title(@period)}
          title={@cg.label}
        >
          <:actions>
            <span
              id="council-status"
              class={[
                "badge",
                if(@council.status == :held, do: "badge-success", else: "badge-warning")
              ]}
            >
              {if @council.status == :held, do: gettext("Tenu"), else: gettext("Ouvert")}
            </span>
          </:actions>
        </.page_header>

        <div role="tablist" class="tabs tabs-box w-fit">
          <.link
            :for={t <- @terms}
            role="tab"
            patch={~p"/school/councils/#{@cg.id}?term=#{t.id}"}
            class={["tab", @period == {:trimester, t} && "tab-active"]}
          >
            {gettext("Trimestre %{n}", n: t.position)}
          </.link>
          <.link
            role="tab"
            patch={~p"/school/councils/#{@cg.id}?period=annee"}
            class={["tab", annual?(@period) && "tab-active"]}
          >
            {gettext("Année")}
          </.link>
        </div>

        <p :if={@locked?} id="council-locked" class="alert alert-info text-sm">
          <.icon name="hero-lock-closed" class="size-4" />
          {gettext("Conseil verrouillé : bulletins publiés.")}
        </p>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <.form
            for={%{}}
            as={:council}
            id="council-header-form"
            phx-submit="save_header"
            class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                type="date"
                name="council[held_on]"
                value={@council.held_on}
                label={gettext("Date du conseil")}
                disabled={@locked?}
              />
              <.input
                name="council[chair]"
                value={@council.chair}
                label={gettext("Président")}
                disabled={@locked?}
              />
            </div>
            <.input
              type="textarea"
              name="council[attendees]"
              value={@council.attendees}
              label={gettext("Présents")}
              rows="2"
              disabled={@locked?}
            />
            <.input
              type="textarea"
              name="council[observations]"
              value={@council.observations}
              label={gettext("Observations générales")}
              rows="3"
              disabled={@locked?}
            />
            <button :if={not @locked?} type="submit" class="btn btn-primary btn-sm">
              {gettext("Enregistrer")}
            </button>
          </.form>

          <dl
            id="council-stats"
            class="space-y-2 rounded-box border border-base-300 bg-base-100 p-4 text-sm"
          >
            <div class="flex justify-between">
              <dt>{gettext("Effectif")}</dt>
              <dd class="ta-num">{(@results && @results.effectif) || "—"}</dd>
            </div>
            <div class="flex justify-between">
              <dt>{gettext("Moyenne de la classe")}</dt>
              <dd class="ta-num">{fmt(@results && @results.class_average)}</dd>
            </div>
            <div class="flex justify-between">
              <dt>{gettext("Taux de réussite")}</dt>
              <dd class="ta-num">{pct(@results && @results.pass_rate)}</dd>
            </div>
            <div class="flex justify-between">
              <dt>{gettext("Garçons / Filles")}</dt>
              <dd class="ta-num">
                {fmt(@results && @results.by_sex.m.class_average)} / {fmt(
                  @results && @results.by_sex.f.class_average
                )}
              </dd>
            </div>
            <div class="flex justify-between">
              <dt>{gettext("Saisie des notes")}</dt>
              <dd class="ta-num">{rate_text(@rate)}</dd>
            </div>
          </dl>
        </div>

        <div class="rounded-box border border-base-300 bg-base-100">
          <div class={[
            "hidden gap-3 border-b border-base-300 px-4 py-2 text-xs text-base-content/60 lg:grid",
            grid_cols(@period)
          ]}>
            <span>{gettext("Rang")}</span>
            <span>{gettext("Élève")}</span>
            <span class="text-right">{gettext("Moy.")}</span>
            <span>{gettext("Proposition")}</span>
            <span>{gettext("Décision")}</span>
            <span>{gettext("Conduite")}</span>
            <span>{gettext("Appréciation")}</span>
            <span :if={annual?(@period)}>{gettext("Passage")}</span>
            <span></span>
          </div>
          <.form
            :for={row <- @rows}
            for={%{}}
            as={:decision}
            id={"decision-#{row.student.id}"}
            phx-change="decision"
            class={[
              "grid items-center gap-3 border-b border-base-300 px-4 py-2 last:border-b-0",
              grid_cols(@period)
            ]}
          >
            <input type="hidden" name="student_id" value={row.student.id} />
            <span class="ta-num">{(row.data && row.data.rank) || "—"}</span>
            <span class="font-medium">{row.student.full_name}</span>
            <span class="ta-num text-right">{fmt(row.data && row.data.moyenne_generale)}</span>
            <span><.distinction_badge distinction={row.data && row.data.distinction} /></span>
            <div>
              <span aria-hidden="true" class="mb-1 block text-xs text-base-content/60 lg:hidden">
                {gettext("Décision")}
              </span>
              <.input
                type="select"
                name="decision[distinction_choice]"
                aria-label={gettext("Décision")}
                value={row.decision && row.decision.distinction_choice}
                options={choice_options()}
                class="select select-sm"
                disabled={@locked?}
              />
            </div>
            <div>
              <span aria-hidden="true" class="mb-1 block text-xs text-base-content/60 lg:hidden">
                {gettext("Conduite")}
              </span>
              <.input
                type="select"
                name="decision[conduct_warning]"
                aria-label={gettext("Conduite")}
                value={row.decision && row.decision.conduct_warning}
                options={warning_options()}
                class="select select-sm"
                disabled={@locked?}
              />
            </div>
            <div>
              <span aria-hidden="true" class="mb-1 block text-xs text-base-content/60 lg:hidden">
                {gettext("Appréciation")}
              </span>
              <.input
                name="decision[appreciation]"
                aria-label={gettext("Appréciation")}
                value={row.decision && row.decision.appreciation}
                maxlength="300"
                phx-debounce="blur"
                placeholder={gettext("Appréciation du conseil")}
                class="input input-sm w-full"
                disabled={@locked?}
              />
            </div>
            <div :if={annual?(@period)} id={"passage-#{row.student.id}"} class="space-y-1">
              <p id={"passage-proposal-#{row.student.id}"} class="text-xs text-base-content/70">
                {proposal_text(row.outcome)}
              </p>
              <.input
                type="select"
                name="decision[passage_decision]"
                value={row.decision && row.decision.passage_decision}
                options={passage_options()}
                class="select select-sm"
                disabled={@locked?}
              />
            </div>
            <span
              :if={@saved == row.student.id}
              id={"saved-#{row.student.id}"}
              class="text-xs text-success"
            >
              {gettext("Enregistré")}
            </span>
          </.form>
        </div>

        <div class="flex flex-wrap gap-2">
          <a
            id="print-pv"
            href={~p"/school/councils/#{@cg.id}/print?#{period_params(@period)}"}
            target="_blank"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer le procès-verbal")}
          </a>
        </div>

        <div :if={not @locked?} class="flex flex-wrap gap-2">
          <button
            :if={@council.status != :held}
            id="hold-council"
            type="button"
            phx-click="hold"
            class="btn btn-primary btn-sm"
          >
            {gettext("Marquer le conseil tenu")}
          </button>
          <button
            :if={@council.status == :held}
            id="reopen-council"
            type="button"
            phx-click="reopen"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Rouvrir le conseil")}
          </button>
        </div>

        <div :if={@confirm_hold?} id="hold-confirm" class="alert alert-warning">
          <span>
            {gettext("Saisie incomplète : %{rate}. Marquer tenu quand même ?", rate: rate_text(@rate))}
          </span>
          <div class="flex gap-2">
            <button
              id="confirm-hold"
              type="button"
              phx-mounted={JS.focus()}
              phx-click="confirm_hold"
              class="btn btn-sm btn-warning"
            >
              {gettext("Marquer tenu")}
            </button>
            <button type="button" phx-click="cancel" class="btn btn-sm btn-ghost">
              {gettext("Annuler")}
            </button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
