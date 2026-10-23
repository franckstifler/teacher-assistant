defmodule TeacherAssistantWeb.School.CouncilLive do
  @moduledoc """
  One class's council for a trimester (spec I3) or the year (spec I4, with a passage
  column): the header (date, président, présents,
  observations générales), the class statistics, and a row per student — rank,
  average, conduct and the council's distinction choice as one select (the I1
  proposal preselected), with a count of each decision above; the conduct warning,
  appreciation and passage sit under « Détails du conseil ». Each row saves on
  change. « Clôturer le conseil » (confirmation below complete entry), « Rouvrir »
  and « Imprimer le PV » in the « ⋯ » menu; everything read-only once the term is
  published.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Assessment, Councils, Discipline, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistantWeb.{Dates, Numbers}

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

  # Everything the page shows for the class and period. Writes on this page touch only
  # the council, so after one `refresh_council/1` is enough.
  defp load(socket) do
    %{current_scope: scope, cg: cg, period: period, year: year} = socket.assigns
    results = Assessment.class_results_for_period(scope, cg, period)
    discipline = Discipline.class_discipline(scope, cg, period)

    rows =
      scope
      |> Enrollment.list_roster(cg)
      |> Enum.map(fn %{student: s, enrollment: e} ->
        %{
          student: s,
          data: results && results.per_student[s.id],
          decision: nil,
          outcome: nil,
          conduct: discipline[e.id] && discipline[e.id].note_de_conduite
        }
      end)
      |> Enum.sort_by(
        &{(&1.data && &1.data.rank) || 9_999, String.downcase(&1.student.full_name)}
      )

    socket
    |> assign(
      results: results,
      rows: rows,
      rate: EntryProgress.class_rate(scope, year, cg, sequences(scope, period)),
      form_master: Enrollment.form_master(scope, cg)
    )
    |> refresh_council()
  end

  # The council, its decisions and (annual) passage outcomes, on the rows already loaded.
  defp refresh_council(socket) do
    %{current_scope: scope, cg: cg, period: period, results: results, rows: rows} =
      socket.assigns

    council = Councils.council(scope, cg, period)
    decisions = Map.new(council.decisions, &{&1.student_id, &1})
    outcomes = passage_outcomes(scope, cg, period, council, results)

    assign(socket,
      council: council,
      rows:
        Enum.map(
          rows,
          &%{&1 | decision: decisions[&1.student.id], outcome: outcomes[&1.student.id]}
        ),
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
    |> Councils.save_header(cg, period, normalise_time(params))
    |> after_write(socket, gettext("Conseil enregistré."))
  end

  def handle_event("decision", %{"student_id" => student_id} = params, socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    case Councils.set_decision(scope, cg, period, student_id, Map.get(params, "decision", %{})) do
      {:ok, _} -> {:noreply, socket |> refresh_council() |> assign(saved: student_id)}
      other -> after_write(other, socket, nil)
    end
  end

  # The decision select changes only the distinction choice; the student's other stored values
  # are re-sent unchanged. Refused server-side once the council is held or locked.
  def handle_event("choose", %{"student_id" => student_id, "choice" => choice}, socket) do
    %{current_scope: scope, cg: cg, period: period, council: council, locked?: locked?} =
      socket.assigns

    cond do
      locked? or council.status == :held ->
        {:noreply, socket}

      true ->
        current = Enum.find(council.decisions, &(&1.student_id == student_id))

        case Councils.set_decision(scope, cg, period, student_id, keep_values(current, choice)) do
          {:ok, _} -> {:noreply, socket |> refresh_council() |> assign(saved: student_id)}
          other -> after_write(other, socket, nil)
        end
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

  defp keep_values(nil, choice), do: %{"distinction_choice" => choice}

  defp keep_values(decision, choice) do
    %{
      "distinction_choice" => choice,
      "conduct_warning" => to_param(decision.conduct_warning),
      "appreciation" => decision.appreciation,
      "passage_decision" => to_param(decision.passage_decision)
    }
  end

  defp to_param(nil), do: ""
  defp to_param(value), do: to_string(value)

  # `<input type="time">` submits "HH:MM"; Ash's :time cast wants seconds.
  defp normalise_time(%{"starts_at" => <<_::binary-size(5)>> = t} = params) do
    case Time.from_iso8601(t <> ":00") do
      {:ok, time} -> %{params | "starts_at" => time}
      _ -> params
    end
  end

  defp normalise_time(params), do: params

  defp hold(socket) do
    %{current_scope: scope, cg: cg, period: period} = socket.assigns

    scope
    |> Councils.hold(cg, period)
    |> after_write(assign(socket, confirm_hold?: false), gettext("Conseil marqué tenu."))
  end

  defp after_write({:ok, _}, socket, message) do
    socket = refresh_council(socket)
    {:noreply, if(message, do: put_flash(socket, :info, message), else: socket)}
  end

  defp after_write({:error, :locked}, socket, _message) do
    {:noreply,
     socket
     |> refresh_council()
     |> put_flash(:error, gettext("Conseil verrouillé : bulletins publiés."))}
  end

  defp after_write({:error, %Ash.Error.Forbidden{}}, socket, _message),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, _}, socket, _message),
    do: {:noreply, put_flash(socket, :error, gettext("Non enregistré : vérifiez les champs."))}

  # A row's decision: the council's stored choice, else the proposal, else « Aucune ».
  defp pressed_choice(%{decision: %{distinction_choice: choice}}) when choice != nil, do: choice
  defp pressed_choice(%{data: %{distinction: d}}) when d != nil, do: d
  defp pressed_choice(_row), do: :none

  defp eyebrow(period, %{held_on: held_on, starts_at: starts_at}) do
    [
      period_label(period),
      held_on && Dates.long(held_on),
      starts_at && Calendar.strftime(starts_at, "%H:%M")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp period_label({:annual, _}), do: gettext("Année")
  defp period_label({:trimester, term}), do: gettext("Trimestre %{n}", n: term.position)

  defp time_value(nil), do: nil
  defp time_value(time), do: Calendar.strftime(time, "%H:%M")

  defp conduct_text(nil), do: "—"
  defp conduct_text(%Decimal{} = d), do: Numbers.decimal(d, trim: true)
  defp conduct_text(other), do: to_string(other)

  defp rank_text(%{rank: rank}) when is_integer(rank), do: rank
  defp rank_text(_data), do: "—"

  # How many students get each decision (as the rows show it), in the enum's order.
  defp decision_counts(rows) do
    freq = rows |> Enum.map(&pressed_choice/1) |> Enum.frequencies()
    for choice <- CouncilDistinctionChoice.values(), n = freq[choice], do: {choice, n}
  end

  defp choice_badge_class(:none), do: "badge-ghost"
  defp choice_badge_class(:blame_travail), do: "badge-error"
  defp choice_badge_class(:avertissement_travail), do: "badge-warning"
  defp choice_badge_class(_honour), do: "badge-success"

  defp low?(%Decimal{} = d), do: Decimal.lt?(d, 10)
  defp low?(_), do: false

  defp master_name(nil), do: nil
  defp master_name(user), do: User.display_name(user)

  # Only the parts that exist; nil when both the chair and the form master are absent.
  defp header_line(chair, form_master) do
    parts =
      [
        present(chair) && gettext("Présidé par %{chair}", chair: chair),
        master_name(form_master) |> present() |> pp_part()
      ]
      |> Enum.filter(& &1)

    if parts == [], do: nil, else: Enum.join(parts, " · ")
  end

  defp pp_part(nil), do: nil
  defp pp_part(name), do: gettext("PP : %{pp}", pp: name)

  defp present(v) when v in [nil, ""], do: nil
  defp present(v), do: v

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

  defp period_params({:annual, _}), do: %{period: "annee"}
  defp period_params({:trimester, term}), do: %{term: term.id}

  defp warning_options do
    [{gettext("Aucun"), ""}] ++
      Enum.map(ConductWarning.values(), &{ConductWarning.label(&1), &1})
  end

  defp fmt(value), do: Numbers.decimal(value)

  defp pct(nil), do: "—"
  defp pct(rate), do: "#{round(rate * 100)} %"

  defp rate_text(nil), do: "—"
  defp rate_text(rate), do: "#{rate} %"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="council" class="space-y-5">
        <.link
          navigate={~p"/school/councils?#{period_params(@period)}"}
          class="inline-flex items-center gap-1 text-sm text-base-content/70 hover:text-base-content"
        >
          <.icon name="hero-arrow-left" class="size-4" /> {gettext("Conseils de classe")}
        </.link>

        <.page_header
          eyebrow={eyebrow(@period, @council)}
          title={gettext("Conseil de classe · %{class}", class: @cg.label)}
          subtitle={header_line(@council.chair, @form_master)}
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
            <button
              :if={not @locked?}
              id="close-council"
              type="button"
              phx-click="hold"
              disabled={@council.status == :held}
              class="btn btn-primary btn-sm min-h-11 sm:min-h-0"
            >
              {if @council.status == :held,
                do: gettext("Conseil clôturé ✓"),
                else: gettext("Clôturer le conseil")}
            </button>
            <.action_menu id="council-actions" label={gettext("Plus d'actions sur le conseil")}>
              <:item
                href={~p"/school/councils/#{@cg.id}/print?#{period_params(@period)}"}
                target="_blank"
                icon="hero-printer"
              >
                {gettext("Imprimer le PV")}
              </:item>
              <:item
                :if={not @locked? and @council.status == :held}
                id="reopen-council"
                click="reopen"
                icon="hero-lock-open"
              >
                {gettext("Rouvrir")}
              </:item>
            </.action_menu>
          </:actions>
        </.page_header>

        <div role="tablist" class="tabs tabs-box w-fit max-w-full overflow-x-auto">
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

        <section id="council-table" class="ta-section">
          <header class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2 px-4 pb-3 pt-4">
            <h2 class="text-base font-semibold">{gettext("Décisions du conseil")}</h2>
            <p id="decisions-summary" class="flex flex-wrap gap-1.5 text-[0.8rem]">
              <span
                :for={{choice, n} <- decision_counts(@rows)}
                id={"count-#{choice}"}
                class={["badge badge-sm gap-1", choice_badge_class(choice)]}
              >
                {CouncilDistinctionChoice.label(choice)}
                <span class="ta-num font-semibold">{n}</span>
              </span>
            </p>
          </header>
          <div class="hidden grid-cols-[2.5rem_minmax(0,1fr)_5.5rem_5.5rem_15rem] gap-3 border-t border-base-300 px-4 py-2 text-xs text-base-content/70 md:grid">
            <span>{gettext("Rang")}</span>
            <span>{gettext("Élève")}</span>
            <span class="text-right">{gettext("Moyenne")}</span>
            <span class="text-right">{gettext("Conduite")}</span>
            <span>{gettext("Décision")}</span>
          </div>
          <ol>
            <li
              :for={row <- @rows}
              id={"council-row-#{row.student.id}"}
              class="grid grid-cols-[2.5rem_minmax(0,1fr)] items-center gap-x-3 gap-y-2 border-t border-base-300 px-4 py-3 md:grid-cols-[2.5rem_minmax(0,1fr)_5.5rem_5.5rem_15rem]"
            >
              <span class="ta-num grid size-8 place-items-center rounded-full bg-base-200 text-[0.8rem] font-semibold">
                {rank_text(row.data)}
              </span>
              <span class="flex min-w-0 flex-col gap-0.5">
                <span class="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <span class="font-medium leading-snug">{row.student.full_name}</span>
                  <span class={["badge badge-sm", choice_badge_class(pressed_choice(row))]}>
                    {CouncilDistinctionChoice.label(pressed_choice(row))}
                  </span>
                </span>
                <span class="text-[0.8rem] text-base-content/70 md:hidden">
                  {gettext("Moy.")}
                  <span class={[
                    "ta-num font-semibold",
                    low?(row.data && row.data.moyenne_generale) && "text-error"
                  ]}>
                    {Numbers.decimal(row.data && row.data.moyenne_generale)}
                  </span>
                  · {gettext("Conduite")}
                  <span class="ta-num font-semibold">{conduct_text(row.conduct)}</span>
                </span>
              </span>
              <span class={[
                "ta-num hidden text-right font-semibold md:block",
                low?(row.data && row.data.moyenne_generale) && "text-error"
              ]}>
                {Numbers.decimal(row.data && row.data.moyenne_generale)}
              </span>
              <span class="ta-num hidden text-right md:block">{conduct_text(row.conduct)}</span>
              <form
                id={"choice-form-#{row.student.id}"}
                phx-change="choose"
                class="col-span-2 flex items-center gap-2 md:col-span-1"
              >
                <input type="hidden" name="student_id" value={row.student.id} />
                <select
                  id={"choice-#{row.student.id}"}
                  name="choice"
                  aria-label={gettext("Décision pour %{name}", name: row.student.full_name)}
                  disabled={@locked? or @council.status == :held}
                  class="select select-sm h-11 w-full md:h-9"
                >
                  <option
                    :for={choice <- CouncilDistinctionChoice.values()}
                    value={choice}
                    selected={pressed_choice(row) == choice}
                  >
                    {CouncilDistinctionChoice.label(choice)}
                  </option>
                </select>
                <span
                  :if={@saved == row.student.id}
                  id={"saved-#{row.student.id}"}
                  class="shrink-0 text-success"
                  title={gettext("Enregistré")}
                >
                  <.icon name="hero-check-circle" class="size-5" />
                  <span class="sr-only">{gettext("Enregistré")}</span>
                </span>
              </form>
            </li>
          </ol>
        </section>

        <p class="text-xs text-base-content/70">
          {gettext(
            "Les propositions viennent des règles de l'établissement (Paramètres › Appréciations & distinctions). Le conseil peut les modifier ; après clôture, elles figurent sur les bulletins du trimestre."
          )}
        </p>

        <details id="council-details" class="rounded-box border border-base-300 bg-base-100">
          <summary class="cursor-pointer px-4 py-3 font-medium">
            {gettext("Détails du conseil")}
          </summary>
          <div class="space-y-5 border-t border-base-300 p-4">
            <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
              <.form
                for={%{}}
                as={:council}
                id="council-header-form"
                phx-submit="save_header"
                class="space-y-3"
              >
                <div class="grid gap-3 sm:grid-cols-3">
                  <.input
                    type="date"
                    name="council[held_on]"
                    value={@council.held_on}
                    label={gettext("Date du conseil")}
                    disabled={@locked?}
                  />
                  <.input
                    type="time"
                    name="council[starts_at]"
                    value={time_value(@council.starts_at)}
                    label={gettext("Heure")}
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

              <dl id="council-stats" class="space-y-2 text-sm">
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

            <.form
              :for={row <- @rows}
              for={%{}}
              as={:decision}
              id={"decision-#{row.student.id}"}
              phx-change="decision"
              class="grid items-end gap-3 border-t border-base-300 pt-3 sm:grid-cols-2 lg:grid-cols-4"
            >
              <input type="hidden" name="student_id" value={row.student.id} />
              <input
                type="hidden"
                name="decision[distinction_choice]"
                value={row.decision && row.decision.distinction_choice}
              />
              <div class="sm:col-span-2 lg:col-span-4 flex flex-wrap items-center gap-2">
                <span class="font-medium">{row.student.full_name}</span>
                <.distinction_badge distinction={row.data && row.data.distinction} />
              </div>
              <div>
                <span class="mb-1 block text-xs text-base-content/70">{gettext("Conduite")}</span>
                <.input
                  type="select"
                  name="decision[conduct_warning]"
                  aria-label={gettext("Conduite")}
                  value={row.decision && row.decision.conduct_warning}
                  options={warning_options()}
                  class="select select-sm w-full"
                  disabled={@locked?}
                />
              </div>
              <div class="lg:col-span-2">
                <span class="mb-1 block text-xs text-base-content/70">
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
                  class="select select-sm w-full"
                  disabled={@locked?}
                />
              </div>
            </.form>
          </div>
        </details>
      </section>
    </Layouts.app>
    """
  end
end
