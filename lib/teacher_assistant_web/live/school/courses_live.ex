defmodule TeacherAssistantWeb.School.CoursesLive do
  @moduledoc """
  "Mes cours" (UX refonte 2026-11-03): the signed-in teacher's courses in the
  current school as compact rows grouped by subject (« Anglais · 8 cours »), one
  per solo assignment or combined course. A row opens the course's marks page and
  shows its classes, its séquence state (« 3/39 », « 0 éval. ») and, small, the
  coefficient and the form-master badge; results and roster are the course's tabs.
  Filter pills: all, marks to enter, competence to enter (APC schools).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{Lock, Reference, TeacherCourses}
  alias TeacherAssistantWeb.Dates

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
         apc?: Enum.any?(courses, &(&1.competence != nil))
       )}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    filter = if params["f"] in @filters, do: params["f"], else: "all"
    {:noreply, assign(socket, :filter, filter)}
  end

  defp filtered(courses, "marks"), do: Enum.filter(courses, &TeacherCourses.to_enter?/1)
  defp filtered(courses, "competence"), do: Enum.filter(courses, &(&1.competence == :missing))
  defp filtered(courses, _all), do: courses

  # Subjects in the order the courses come, each with its courses.
  defp by_subject(courses) do
    grouped = Enum.group_by(courses, & &1.subject)
    courses |> Enum.map(& &1.subject) |> Enum.uniq() |> Enum.map(&{&1, grouped[&1]})
  end

  defp filter_path("all"), do: ~p"/school/courses"
  defp filter_path(f), do: ~p"/school/courses?f=#{f}"

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

        <.filter_pills :if={@courses != [] && @seq} id="course-filters">
          <:pill
            id="filter-all"
            patch={filter_path("all")}
            count={@counts["all"]}
            current={@filter == "all"}
          >
            {gettext("Tous")}
          </:pill>
          <:pill
            id="filter-marks"
            patch={filter_path("marks")}
            count={@counts["marks"]}
            current={@filter == "marks"}
          >
            {gettext("Notes à saisir")}
          </:pill>
          <:pill
            :if={@apc?}
            id="filter-competence"
            patch={filter_path("competence")}
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
