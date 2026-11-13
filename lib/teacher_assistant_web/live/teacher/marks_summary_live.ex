defmodule TeacherAssistantWeb.Teacher.MarksSummaryLive do
  @moduledoc """
  Résultats of a course in a séquence (UX refonte 2026-11-03): séquence chips with
  their lock state, three figures (average, pass rate, min → max), the five-band
  distribution as one stacked bar, the pass rate by sex and the mentions on one
  line each, then the ranking (ordinal ranks, marks under 10 in coral, Rang / A→Z).
  A combined course gathers every member class, each row naming its class.

  Trimester and year chips (spec audit follow-ups A4) show the same figures from the
  bulletin's subject averages (`Assessment.course_statistics/3`): the published
  snapshot when the period is published, else computed now and labelled provisional.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.TeachingNav

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.Academics.{Lock, Marks, Reference, SchoolTemplates}

  def mount(%{"id" => ctx_id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, ctx} <- Curriculum.fetch_assigned_teaching_context(scope, ctx_id),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, ctx.class_group_id) do
      year = Organization.current_academic_year(scope)
      sequences = if year, do: Organization.list_sequences(scope, year), else: []
      terms = if year, do: Organization.list_terms(scope, year), else: []
      {title, members} = members(scope, ctx, cg)

      {:ok,
       socket
       |> assign(:page_title, "#{title} · #{gettext("Résultats")}")
       |> assign(:ctx, ctx)
       |> assign(:title, title)
       |> assign(:members, members)
       |> assign(:combined?, length(members) > 1)
       |> assign(:sequences, sequences)
       |> assign(:terms, terms)
       |> assign(:year, year)
       |> assign(:students, Enum.flat_map(members, & &1.students))}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  # Every member class of the course (one for a solo course): its context and its
  # students taking the subject, each tagged with the class's label.
  defp members(scope, %{combined_course_id: nil} = ctx, cg),
    do: {"#{ctx.subject} · #{cg.label}", [member(scope, ctx, cg)]}

  defp members(scope, ctx, _cg) do
    {:ok, course} = Curriculum.get_course(scope, ctx.combined_course_id)

    members =
      ctx.combined_course_id
      |> Curriculum.contexts_of_course!(scope: scope)
      |> Ash.load!(:class_group, scope: scope)
      |> Enum.sort_by(&SchoolTemplates.class_sort_key(&1.class_group))
      |> Enum.map(&member(scope, &1, &1.class_group))

    {course.label, members}
  end

  defp member(scope, ctx, cg) do
    exempt = Curriculum.exempt_student_ids(scope, ctx)

    students =
      for s <- Enrollment.list_students(scope, cg), not MapSet.member?(exempt, s.id) do
        %{id: s.id, sex: s.sex, full_name: s.full_name, class_label: cg.label}
      end

    %{ctx: ctx, class_group: cg, students: students}
  end

  def handle_params(params, _uri, socket) do
    sort = if params["sort"] == "az", do: "az", else: "rank"
    period = pick_period(socket.assigns, params)
    seq = with {:sequence, seq} <- period, do: seq, else: (_ -> nil)

    {:noreply, socket |> assign(period: period, seq: seq, sort: sort) |> assign_summary()}
  end

  # `?seq=` wins, then `?period=trim:<id>|annee`, then the séquence under way (as « Notes »).
  defp pick_period(%{sequences: sequences} = assigns, params) do
    cond do
      seq = pick(sequences, params["seq"]) -> {:sequence, seq}
      period = resolve(assigns, params["period"]) -> period
      seq = Assessment.default_sequence(sequences, Reference.today()) -> {:sequence, seq}
      true -> nil
    end
  end

  defp resolve(_assigns, nil), do: nil
  defp resolve(%{year: nil}, _param), do: nil

  defp resolve(%{year: year, current_scope: scope}, param),
    do: Organization.resolve_period(scope, year, param)

  defp summary_path(assigns, overrides) do
    params =
      [
        seq: assigns.seq && assigns.seq.id,
        period:
          is_nil(assigns.seq) && assigns.period && Organization.period_param(assigns.period),
        sort: assigns.sort != "rank" && assigns.sort
      ]
      |> Keyword.merge(overrides)
      |> Enum.reject(fn {_k, v} -> v in [nil, false] end)

    ~p"/teacher/contexts/#{assigns.ctx.id}/marks/summary?#{params}"
  end

  defp assign_summary(%{assigns: %{period: nil}} = socket),
    do: assign(socket, summary: nil, source: :live)

  defp assign_summary(socket) do
    %{ctx: ctx, period: period, current_scope: scope} = socket.assigns
    stats = Assessment.course_statistics(scope, ctx, period)
    # The period's students (A7: a student who left during it is still ranked).
    assign(socket, summary: stats.summary, source: stats.source, students: stats.students)
  end

  defp period_chosen?({:trimester, %{id: id}}, {:trimester, %{id: id}}), do: true
  defp period_chosen?({:annual, _}, {:annual, _}), do: true
  defp period_chosen?(_period, _chip), do: false

  defp eyebrow({:sequence, seq}), do: gettext("Résultats · Séquence %{n}", n: seq.number)
  defp eyebrow({:trimester, term}), do: gettext("Résultats · Trimestre %{n}", n: term.position)
  defp eyebrow({:annual, _}), do: gettext("Résultats · Année")
  defp eyebrow(nil), do: gettext("Résultats")

  defp source_line(:published), do: gettext("Chiffres du bulletin publié")

  defp source_line(:mixed),
    do:
      gettext("Chiffres en partie provisoires (bulletin publié pour certaines classes seulement)")

  defp source_line(_live), do: gettext("Chiffres provisoires (bulletin non publié)")

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, &(&1.id == id))

  # « Séq. 1 · verrouillée », « Séq. 2 · en cours », « Séq. 3 · à venir »
  defp seq_label(seq) do
    state =
      cond do
        Lock.locked?(seq) -> gettext("verrouillée")
        Lock.not_started?(seq) -> gettext("à venir")
        true -> gettext("en cours")
      end

    gettext("Séq. %{n}", n: seq.number) <> " · " <> state
  end

  defp fmt(nil), do: "—"

  defp fmt(%Decimal{} = d),
    do: d |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp short(nil), do: "—"
  # « 8 », « 12,5 »: the range keeps one decimal at most.
  defp short(%Decimal{} = d),
    do:
      d
      |> Decimal.round(1)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

  defp pct(rate), do: "#{round(rate * 100)} %"

  defp low?(%Decimal{} = d), do: Decimal.lt?(d, 10)
  defp low?(_), do: false

  # The five domain bands, best last, each with its share of the graded students.
  defp distribution(summary),
    do: summary.per_student |> Map.values() |> Enum.map(& &1.average) |> Marks.distribution()

  defp band_tone(%{below_pass?: true}, _i), do: "bg-error text-error-content"
  defp band_tone(_band, 2), do: "bg-primary/45 text-base-content"
  defp band_tone(_band, 3), do: "bg-primary/70 text-primary-content"
  defp band_tone(_band, _i), do: "bg-primary text-primary-content"

  # « Excellent ×2 · Bien ×3 », best first.
  defp mentions_line(summary) do
    summary.per_student
    |> Map.values()
    |> Enum.reject(&is_nil(&1.mention))
    |> Enum.frequencies_by(& &1.mention)
    |> Enum.sort_by(fn {mention, _count} -> mention.position end, :desc)
    |> Enum.map_join(" · ", fn {mention, count} -> "#{mention.label} ×#{count}" end)
  end

  # « Réussite filles 75 % · garçons 50 % » (a sex without marks reads « — »).
  defp sex_line(%{by_sex: %{f: f, m: m}}),
    do:
      gettext("Réussite filles %{f} · garçons %{m}",
        f: sex_rate(f),
        m: sex_rate(m)
      )

  defp sex_rate(%{graded_count: 0}), do: "—"
  defp sex_rate(%{pass_rate: rate}), do: pct(rate)

  defp ranking(students, _summary, "az"),
    do: Enum.sort_by(students, &String.downcase(&1.full_name))

  defp ranking(students, summary, _rank) do
    Enum.sort_by(students, fn s ->
      {summary.per_student[s.id].rank || 9_999, String.downcase(s.full_name)}
    end)
  end

  defp ordinal(nil), do: "—"

  defp ordinal(n),
    do:
      TeacherAssistantWeb.School.BulletinsLive.ordinal(
        Gettext.get_locale(TeacherAssistantWeb.Gettext),
        n
      )

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["courses"]}
      immersive
    >
      <section id="teacher-marks-summary" class="mx-auto max-w-2xl space-y-4">
        <.teaching_nav context_id={@ctx.id} label={@title} current={:summary} />

        <header class="hidden sm:block">
          <p class="ta-eyebrow">{eyebrow(@period)}</p>
          <h1 class="text-2xl font-semibold leading-tight sm:text-[2rem]">{@title}</h1>
          <p :if={@summary} class="text-[0.95rem] text-base-content/75">
            {ngettext("%{count} élève", "%{count} élèves", length(@students))} · {ngettext(
              "%{count} note",
              "%{count} notes",
              @summary.graded_count
            )}
          </p>
        </header>

        <nav
          :if={@sequences != []}
          id="summary-seq-chips"
          role="tablist"
          aria-label={gettext("Séquence")}
          class="ta-pills"
        >
          <.link
            :for={s <- @sequences}
            id={"summary-seq-#{s.id}"}
            role="tab"
            patch={summary_path(assigns, seq: s.id)}
            aria-selected={to_string(@seq && @seq.id == s.id)}
            aria-current={@seq && @seq.id == s.id && "true"}
            class="ta-pill"
          >
            {seq_label(s)}
          </.link>
          <.link
            :for={t <- @terms}
            id={"summary-period-trim-#{t.id}"}
            role="tab"
            patch={summary_path(assigns, seq: nil, period: "trim:#{t.id}")}
            aria-selected={to_string(period_chosen?(@period, {:trimester, t}))}
            aria-current={period_chosen?(@period, {:trimester, t}) && "true"}
            class="ta-pill"
          >
            {gettext("Trim. %{n}", n: t.position)}
          </.link>
          <.link
            :if={@terms != []}
            id="summary-period-annee"
            role="tab"
            patch={summary_path(assigns, seq: nil, period: "annee")}
            aria-selected={to_string(period_chosen?(@period, {:annual, nil}))}
            aria-current={period_chosen?(@period, {:annual, nil}) && "true"}
            class="ta-pill"
          >
            {gettext("Année")}
          </.link>
        </nav>

        <p
          :if={is_nil(@seq) and not is_nil(@period)}
          id="summary-provisional"
          class={[
            "flex items-center gap-2 text-sm",
            if(@source == :published, do: "text-success", else: "text-warning")
          ]}
        >
          <.icon
            name={if @source == :published, do: "hero-check-badge", else: "hero-clock"}
            class="size-4"
          />
          {source_line(@source)}
        </p>

        <%= if @summary do %>
          <section
            id="summary-stats"
            aria-label={gettext("Synthèse")}
            class="grid grid-cols-3 gap-px overflow-hidden rounded-box border border-base-300 bg-base-300"
          >
            <div id="summary-class-average" class="bg-base-100 p-3">
              <p class="text-xs text-base-content/70">{gettext("Moyenne")}</p>
              <p class={[
                "ta-num mt-0.5 text-[1.35rem] font-semibold",
                low?(@summary.class_average) && "text-error"
              ]}>
                {fmt(@summary.class_average)}
              </p>
            </div>
            <div id="summary-pass-rate" class="bg-base-100 p-3">
              <p class="text-xs text-base-content/70">{gettext("Réussite")}</p>
              <p class="ta-num mt-0.5 text-[1.35rem] font-semibold text-primary">
                {pct(@summary.pass_rate)}
              </p>
            </div>
            <div id="summary-range" class="bg-base-100 p-3">
              <p class="text-xs text-base-content/70">{gettext("Écart")}</p>
              <p class="ta-num mt-0.5 text-base font-semibold leading-[2rem]">
                {short(@summary.lowest)} → {short(@summary.highest)}
              </p>
            </div>
          </section>

          <section
            id="summary-distribution"
            aria-label={gettext("Répartition des notes")}
            class="space-y-2"
          >
            <div
              :if={@summary.graded_count > 0}
              class="ta-num flex h-7 overflow-hidden rounded-field text-xs font-semibold"
              aria-hidden="true"
            >
              <span
                :for={{b, i} <- Enum.with_index(distribution(@summary))}
                :if={b.count > 0}
                class={["grid place-items-center", band_tone(b, i)]}
                style={"flex: #{b.count}"}
              >
                {b.count}
              </span>
            </div>
            <ul class="ta-num flex flex-wrap gap-x-3 gap-y-1 text-[0.72rem] text-base-content/70">
              <li
                :for={{b, i} <- Enum.with_index(distribution(@summary))}
                data-band={b.label}
                class="flex items-center gap-1"
              >
                <span class={["size-2 rounded-full", band_tone(b, i)]}></span>
                {b.label} · {b.count}
              </li>
            </ul>
            <p id="summary-sex" class="text-xs text-base-content/70">{sex_line(@summary)}</p>
            <p id="summary-mentions" class="text-xs text-base-content/70">
              {mentions_line(@summary)}
            </p>
          </section>

          <p
            :if={length(@students) > @summary.graded_count}
            id="summary-missing"
            class="flex items-center gap-2 text-sm text-warning"
          >
            <.icon name="hero-exclamation-triangle" class="size-4" />
            <%!-- an ABJ alone leaves no average either, so « sans moyenne », not « sans note » --%>
            {if @seq,
              do:
                ngettext(
                  "%{count} élève sans moyenne dans cette séquence (note manquante ou ABJ)",
                  "%{count} élèves sans moyenne dans cette séquence (notes manquantes ou ABJ)",
                  length(@students) - @summary.graded_count
                ),
              else:
                ngettext(
                  "%{count} élève sans moyenne sur cette période",
                  "%{count} élèves sans moyenne sur cette période",
                  length(@students) - @summary.graded_count
                )}
          </p>

          <section id="summary-table" aria-label={gettext("Classement")}>
            <div class="mb-1.5 flex items-center justify-between gap-2">
              <h2 class="px-1 text-xs font-semibold uppercase tracking-wide text-base-content/70">
                {gettext("Classement")}
              </h2>
              <div role="group" aria-label={gettext("Trier")} class="flex gap-1">
                <.link
                  id="sort-rank"
                  patch={summary_path(assigns, sort: false)}
                  aria-pressed={to_string(@sort == "rank")}
                  class={["btn btn-xs h-8", if(@sort == "rank", do: "btn-neutral", else: "btn-ghost")]}
                >
                  {gettext("Rang")}
                </.link>
                <.link
                  id="sort-az"
                  patch={summary_path(assigns, sort: "az")}
                  aria-pressed={to_string(@sort == "az")}
                  class={["btn btn-xs h-8", if(@sort == "az", do: "btn-neutral", else: "btn-ghost")]}
                >
                  {gettext("A → Z")}
                </.link>
              </div>
            </div>
            <ol class="ta-section">
              <li
                :for={s <- ranking(@students, @summary, @sort)}
                id={"summary-row-#{s.id}"}
                class="flex min-h-12 items-center gap-3 border-t border-base-300/60 px-4 py-1.5 first:border-t-0"
              >
                <span class="ta-num w-9 shrink-0 text-xs font-semibold text-base-content/70">
                  {ordinal(@summary.per_student[s.id].rank)}
                </span>
                <span class="flex min-w-0 flex-1 flex-col">
                  <span class="truncate text-[0.92rem]">{s.full_name}</span>
                  <span :if={@combined?} class="ta-num text-[0.7rem] text-base-content/70">
                    {s.class_label}
                  </span>
                </span>
                <span class={[
                  "shrink-0 text-xs",
                  if(low?(@summary.per_student[s.id].average),
                    do: "text-error",
                    else: "text-base-content/70"
                  )
                ]}>
                  {if @summary.per_student[s.id].mention,
                    do: @summary.per_student[s.id].mention.label,
                    else: gettext("Pas de note")}
                </span>
                <span class={[
                  "ta-num w-12 shrink-0 text-right text-[0.95rem] font-semibold",
                  low?(@summary.per_student[s.id].average) && "text-error"
                ]}>
                  {fmt(@summary.per_student[s.id].average)}
                </span>
              </li>
            </ol>
          </section>
        <% else %>
          <p :if={@sequences == []} class="ta-leaf">
            {gettext("Pas encore de séquences — configurez d'abord l'année scolaire.")}
          </p>
          <.empty_state
            :if={@sequences != []}
            icon="hero-pencil-square"
            title={
              if @seq,
                do: gettext("Pas encore de notes dans cette séquence"),
                else: gettext("Pas encore de moyenne sur cette période")
            }
            message={
              gettext("Saisissez les notes d'une évaluation pour voir les résultats de la séquence.")
            }
          >
            <:action>
              <.link
                navigate={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{@seq && @seq.id}"}
                class="btn btn-primary btn-sm"
              >
                {gettext("Saisir les notes")}
              </.link>
            </:action>
          </.empty_state>
        <% end %>

        <.link
          :if={@period}
          id="summary-all"
          navigate={~p"/school/statistics/me?#{[period: Organization.period_param(@period)]}"}
          class="flex min-h-11 items-center justify-center gap-2 text-sm font-medium text-primary hover:underline"
        >
          <.icon name="hero-chart-bar" class="size-4" />
          {gettext("Toutes mes statistiques")}
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
