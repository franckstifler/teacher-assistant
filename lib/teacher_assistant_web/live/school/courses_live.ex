defmodule TeacherAssistantWeb.School.CoursesLive do
  @moduledoc """
  "Mes cours" (UX refonte 2026-11-03): the signed-in teacher's courses in the
  current school as compact rows grouped by subject (« Anglais · 8 cours »), one
  per solo assignment or combined course. A row opens the course's marks page and
  shows its classes, its séquence state (« 3/39 », « 0 éval. ») and, small, the
  coefficient and the form-master badge; results and roster are the course's tabs.
  Filter pills: all, marks to enter, competence to enter (APC schools).

  Above them (spec audit follow-ups A5, from the teacher's former Bulletins view):
  the trimester / year pills and the road to the period's bulletins — each
  séquence's marks with its deadline, the councils, the publication — collapsed to
  the current step on phones. A row links to the course's statistics.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Organization, ReportCards, Scope}
  alias TeacherAssistant.Academics.{Lock, Reference, TeacherCourses}
  alias TeacherAssistantWeb.{BulletinTimeline, Dates}

  @filters ~w(all marks competence)

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil do
      today = Reference.today()
      seq = TeacherCourses.current_sequence(scope, today)
      courses = TeacherCourses.list(scope, seq)

      {:ok,
       assign(socket,
         page_title: gettext("Mes cours"),
         courses: courses,
         seq: seq,
         today: today,
         # Each class once, even when the teacher has it in two subjects.
         student_total: TeacherCourses.student_total(courses),
         counts: %{
           "all" => length(courses),
           "marks" => Enum.count(courses, &TeacherCourses.to_enter?/1),
           "competence" => Enum.count(courses, &(&1.competence == :missing))
         },
         apc?: Enum.any?(courses, &(&1.competence != nil)),
         notes?: Scope.module?(scope, :notes),
         periods: bulletin_periods(scope)
       )}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    filter = if params["f"] in @filters, do: params["f"], else: "all"
    {:noreply, socket |> assign(:filter, filter) |> assign_timeline(params["period"])}
  end

  # Trimesters and the year (the séquences have their own row states), with the
  # Notes module only.
  defp bulletin_periods(%Scope{current_academic_year: nil}), do: []

  defp bulletin_periods(%Scope{current_academic_year: year} = scope) do
    if Scope.module?(scope, :notes),
      do: scope |> ReportCards.periods(year) |> Enum.reject(&match?({_, _, {:sequence, _}}, &1)),
      else: []
  end

  defp assign_timeline(%{assigns: %{periods: []}} = socket, _param),
    do: assign(socket, period_param: nil, chosen_period: nil, steps: [])

  defp assign_timeline(socket, param) do
    %{periods: periods, seq: seq, courses: courses, current_scope: scope, today: today} =
      socket.assigns

    chosen = Enum.find(periods, &(elem(&1, 0) == param))
    {param, _label, period} = chosen || default_period(periods, seq)

    published = ReportCards.published_class_ids(scope, period)
    classes = courses |> Enum.flat_map(& &1.classes) |> Enum.uniq_by(& &1.id)
    published? = classes != [] and Enum.all?(classes, &MapSet.member?(published, &1.id))

    assign(socket,
      period_param: param,
      # Kept in the filter links only when the teacher picked it.
      chosen_period: chosen && param,
      steps: BulletinTimeline.steps(period_sequences(scope, period), published?, today)
    )
  end

  # The trimester of the current séquence, else the year.
  defp default_period(periods, seq) do
    (seq &&
       Enum.find(periods, &match?({_, _, {:trimester, %{id: id}}} when id == seq.term_id, &1))) ||
      List.last(periods)
  end

  # `list_sequences` loads each séquence's grade-entry deadline.
  defp period_sequences(scope, {:trimester, term}),
    do:
      scope
      |> Organization.list_sequences(term_year(scope))
      |> Enum.filter(&(&1.term_id == term.id))

  defp period_sequences(scope, {:annual, year}), do: Organization.list_sequences(scope, year)

  defp term_year(%Scope{current_academic_year: year}), do: year

  defp period_path(params) do
    case Enum.reject(params, fn {_k, v} -> v in [nil, "all"] end) do
      [] -> ~p"/school/courses"
      query -> ~p"/school/courses?#{query}"
    end
  end

  defp filtered(courses, "marks"), do: Enum.filter(courses, &TeacherCourses.to_enter?/1)
  defp filtered(courses, "competence"), do: Enum.filter(courses, &(&1.competence == :missing))
  defp filtered(courses, _all), do: courses

  # Subjects in the order the courses come, each with its courses.
  defp by_subject(courses) do
    grouped = Enum.group_by(courses, & &1.subject)
    courses |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.map(&{&1, grouped[&1]})
  end

  defp filter_path(f, period_param), do: period_path(f: f, period: period_param)

  defp coef_label(n), do: TeacherAssistantWeb.Numbers.decimal(n, trim: true)

  defp subtitle(courses, students, seq, today) do
    base =
      ngettext("%{count} cours", "%{count} cours", length(courses)) <>
        " · " <> ngettext("%{count} élève", "%{count} élèves", students)

    if seq && not Lock.locked?(seq, today) do
      base <>
        " · " <>
        gettext("Séq. %{n} jusqu'au %{date}",
          n: seq.number,
          date: Dates.day_month(seq.grade_entry_deadline)
        )
    else
      base
    end
  end

  # « Niveau 2 · 5 classes » for a combined course over several classes.
  defp row_title(%{classes: [_, _ | _] = classes, name: name}),
    do: name <> " · " <> ngettext("%{count} classe", "%{count} classes", length(classes))

  defp row_title(course), do: course.name

  # « COME 2 · ELEQ 2 — 39 él. » for a combined course, « 6 élèves » for one class.
  defp classes_line(%{classes: [_, _ | _] = classes, students: n}),
    do:
      Enum.map_join(classes, " · ", & &1.label) <>
        " — " <> ngettext("%{count} él.", "%{count} él.", n)

  defp classes_line(%{students: n}), do: ngettext("%{count} élève", "%{count} élèves", n)

  def render(assigns) do
    assigns = assign(assigns, :shown, filtered(assigns.courses, assigns.filter))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="courses" class="mx-auto max-w-3xl space-y-4">
        <header class="space-y-1">
          <p :if={@current_scope.current_academic_year} class="ta-eyebrow hidden sm:block">
            {gettext("Enseignement")} · {@current_scope.current_academic_year.name}
          </p>
          <h1 class="text-2xl font-semibold leading-tight sm:text-[2rem]">{gettext("Mes cours")}</h1>
          <p :if={@courses != []} id="courses-subtitle" class="text-[0.95rem] text-base-content/75">
            {subtitle(@courses, @student_total, @seq, @today)}
            <span
              :if={
                @seq && !Lock.locked?(@seq, @today) &&
                  Dates.countdown(@seq.grade_entry_deadline, @today)
              }
              class="ta-num whitespace-nowrap font-semibold text-warning"
            >
              · {Dates.countdown(@seq.grade_entry_deadline, @today)}
            </span>
          </p>
          <a
            :if={@courses != []}
            id="print-all-class-lists"
            href={~p"/teacher/class-lists/print"}
            target="_blank"
            class="btn btn-outline btn-sm mt-2 min-h-11 gap-1.5 sm:min-h-0"
          >
            <.icon name="hero-printer" class="size-4" />
            {gettext("Imprimer mes listes de classe")}
          </a>
        </header>

        <div :if={@courses == []} id="courses-empty">
          <.empty_state
            icon="hero-academic-cap"
            title={gettext("Aucun cours attribué")}
            message={
              gettext(
                "Un administrateur de l'établissement doit vous attribuer une matière dans une classe."
              )
            }
          />
        </div>

        <section :if={@courses != [] and @steps != []} id="courses-bulletins" class="space-y-3">
          <BulletinTimeline.period_pills
            id="courses-period-tabs"
            periods={@periods}
            current={@period_param}
            patch={&period_path(f: @filter, period: &1)}
          />
          <BulletinTimeline.timeline id="bulletin-timeline" steps={@steps} />
        </section>

        <.filter_pills :if={@courses != [] && @seq} id="course-filters">
          <:pill
            id="filter-all"
            patch={filter_path("all", @chosen_period)}
            count={@counts["all"]}
            current={@filter == "all"}
          >
            {gettext("Tous")}
          </:pill>
          <:pill
            id="filter-marks"
            patch={filter_path("marks", @chosen_period)}
            count={@counts["marks"]}
            current={@filter == "marks"}
          >
            {gettext("Notes à saisir")}
          </:pill>
          <:pill
            :if={@apc?}
            id="filter-competence"
            patch={filter_path("competence", @chosen_period)}
            count={@counts["competence"]}
            current={@filter == "competence"}
          >
            {gettext("Compétence")}
          </:pill>
        </.filter_pills>

        <p
          :if={@courses != [] && @shown == []}
          id="courses-filtered-empty"
          class="ta-leaf text-sm text-base-content/75"
        >
          {gettext("Aucun cours dans ce filtre.")}
        </p>

        <section
          :for={{subject, rows} <- by_subject(@shown)}
          aria-label={subject}
          class="space-y-1.5"
        >
          <h2 class="px-1 text-xs font-semibold uppercase tracking-wide text-base-content/70">
            {subject} · {ngettext("%{count} cours", "%{count} cours", length(rows))}
          </h2>
          <ul class="ta-section">
            <li :for={course <- rows} id={"course-#{course.id}"} class="ta-list-row !p-0">
              <.link
                navigate={course_path(course, @seq)}
                class="flex min-h-14 min-w-0 flex-1 items-center gap-3 px-4 py-2 transition-colors hover:bg-base-content/5"
              >
                <span class="flex min-w-0 flex-1 flex-col gap-0.5">
                  <span class="flex items-center gap-2">
                    <span class="truncate text-[0.95rem] font-semibold">{row_title(course)}</span>
                    <span
                      :if={course.pp?}
                      data-role="pp"
                      title={gettext("Professeur principal")}
                      class="badge badge-xs shrink-0 border-0 bg-warning/20 font-semibold text-warning"
                    >
                      PP
                    </span>
                  </span>
                  <span class="ta-num truncate text-[0.72rem] text-base-content/70">
                    {classes_line(course)}<span :if={course.coefficient}> · {gettext("coef. %{n}",
                      n: coef_label(course.coefficient)
                    )}</span>
                  </span>
                  <span
                    :if={@seq && course.competence}
                    data-role="competence"
                    class={[
                      "text-[0.72rem]",
                      if(course.competence == :missing,
                        do: "font-semibold text-warning",
                        else: "text-base-content/70"
                      )
                    ]}
                  >
                    <%= if course.competence == :missing do %>
                      {gettext("Compétence Séq. %{n} : à saisir", n: @seq.number)}
                    <% else %>
                      {gettext("Compétence Séq. %{n} ✓", n: @seq.number)}
                    <% end %>
                  </span>
                </span>
                <.state_pill :if={@seq} progress={course.progress} />
                <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/70" />
              </.link>
              <.link
                :if={@seq && @notes?}
                id={"course-stats-#{course.id}"}
                navigate={~p"/school/statistics/me?#{[period: "seq:#{@seq.id}"]}"}
                aria-label={gettext("Statistiques du cours")}
                title={gettext("Statistiques du cours")}
                class="flex min-h-14 shrink-0 items-center gap-1 border-l border-base-300/60 px-3 text-xs font-medium text-primary transition-colors hover:bg-base-content/5"
              >
                <.icon name="hero-chart-bar" class="size-4" />
                <span class="max-sm:hidden">{gettext("Stats")}</span>
              </.link>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end

  # The séquence's marks page: with the séquence in the URL when a competence is due,
  # so the competence form opens on it.
  defp course_path(%{competence: :missing, context_id: id}, %{id: seq_id}),
    do: ~p"/teacher/contexts/#{id}/marks?seq=#{seq_id}"

  defp course_path(%{context_id: id}, _seq), do: ~p"/teacher/contexts/#{id}/marks"

  @doc "« 3/39 » (amber while incomplete, green ✓ once complete) or « 0 éval. »."
  attr :progress, :map, required: true

  def state_pill(assigns) do
    ~H"""
    <span
      data-role="progress"
      class={[
        "ta-num shrink-0 whitespace-nowrap rounded-full px-2 py-1 text-[0.72rem] font-semibold",
        state_tone(@progress)
      ]}
    >
      <%= cond do %>
        <% @progress.assessments == 0 -> %>
          {gettext("0 éval.")}
        <% @progress.expected > 0 and @progress.entered >= @progress.expected -> %>
          {@progress.entered}/{@progress.expected} ✓
        <% true -> %>
          {@progress.entered}/{@progress.expected}
      <% end %>
    </span>
    """
  end

  defp state_tone(%{assessments: 0}), do: "bg-warning/15 text-warning"

  defp state_tone(%{entered: e, expected: x}) when x > 0 and e >= x,
    do: "bg-success/15 text-success"

  defp state_tone(_progress), do: "bg-warning/15 text-warning"
end
