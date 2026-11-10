defmodule TeacherAssistantWeb.School.MyDayLive do
  @moduledoc """
  Enseignant → Ma journée (spec G, V01/V03; UX refonte 2026-11-03). Phone first:

    * a « Maintenant » card for the lesson in progress (else the next one, else the
      last missed one) with « Faire l'appel » and « Notes »;
    * the roll call of the selected lesson (`?slot=<class>-<period>`) in its place
      once opened, names in full and a sticky « Valider l'appel »;
    * today's lessons, a combined course once per period with its students, breaks
      as thin separators — a lesson whose roll call can be taken opens it;
    * « À faire »: the séquence's marks still to enter, with its deadline;
    * this week's missed roll calls, folded to a count line.

  From `lg`: the now-card lies flat with both buttons in a row, the séquence's
  courses with their progress and next step sit under it, today's lessons on the right.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.{LessonGroups, Lock, Reference, TeacherCourses}
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.School.{LessonComponents, RollCall}

  import LessonComponents, only: [hm: 1, status_tag: 1]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         [_ | _] = units <- Curriculum.list_units_for_scope(scope) do
      today = Reference.today()
      seq = TeacherCourses.current_sequence(scope, today)

      {:ok,
       socket
       |> assign(
         page_title: gettext("Ma journée"),
         today: today,
         roll: nil,
         selected: nil,
         seq: seq,
         labels: LessonComponents.course_labels(units),
         sizes: Enrollment.class_sizes(scope, scope.current_academic_year),
         courses: TeacherCourses.list(scope, seq),
         breaks: scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :break))
       )
       |> load_day()}
    else
      _ -> {:ok, push_navigate(socket, to: space_home(scope))}
    end
  end

  defp space_home(%{capabilities: %{space: %{home: home}}}) when home != "/school/today", do: home
  defp space_home(_scope), do: ~p"/school/classes"

  defp load_day(socket) do
    %{current_scope: scope, today: today} = socket.assigns
    now = Reference.now()
    user = scope.current_user

    assign(socket,
      now: now,
      lessons: Attendance.teacher_lessons(scope, user, today, now),
      day_off: Attendance.day_off(scope, today),
      missed:
        scope |> Attendance.teacher_missed_this_week(user, today, now) |> LessonGroups.group()
    )
  end

  # The roll call opens only on demand (« Faire l'appel », a tap on a lesson):
  # `?slot=` names a lesson whose roll call can be taken (not upcoming). A combined
  # course opens through its first class, and the roll covers every member class.
  def handle_params(params, _uri, socket) do
    %{lessons: lessons, current_scope: scope, today: today} = socket.assigns

    case Enum.find(lessons, &(&1.status != :upcoming and &1.key == params["slot"])) do
      nil ->
        {:noreply, assign(socket, selected: nil, roll: nil)}

      lesson ->
        [first | _] = lesson.members

        roll =
          case RollCall.open(scope, first.class_group.id, lesson.period.id, today,
                 following: true
               ) do
            {:ok, roll} -> roll
            {:error, _} -> nil
          end

        {:noreply, assign(socket, selected: roll && lesson.key, roll: roll)}
    end
  end

  def handle_event("all_present", _params, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.all_present(&1)))}

  def handle_event("minutes", %{"minutes" => minutes}, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.set_minutes(&1, minutes)))}

  def handle_event("set", %{"enrollment_id" => id, "status" => status}, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.toggle(&1, id, status)))}

  def handle_event("toggle_following", _params, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.toggle_following(&1)))}

  def handle_event("record", _params, %{assigns: %{roll: %{}}} = socket) do
    case RollCall.record(socket.assigns.current_scope, socket.assigns.roll) do
      {:ok, roll} ->
        {:noreply,
         socket
         |> assign(:roll, roll)
         |> load_day()
         |> put_flash(:info, gettext("Appel enregistré"))}

      {:error, reason} ->
        {:noreply, RollCall.put_error(socket, reason)}
    end
  end

  def handle_event("record", _params, socket), do: {:noreply, socket}

  defp no_lessons_title({:holiday, label}), do: gettext("Jour férié : %{label}", label: label)
  defp no_lessons_title(_), do: gettext("Pas de cours aujourd'hui")

  def render(assigns) do
    assigns =
      assign(assigns,
        focus: focus_lesson(assigns.lessons, NaiveDateTime.to_time(assigns.now)),
        selected_lesson: Enum.find(assigns.lessons, &(&1.key == assigns.selected)),
        open?: assigns.seq && not Lock.locked?(assigns.seq, assigns.today),
        todo: todo(assigns.courses)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-day" class="flex flex-col gap-5">
        <header class="space-y-1">
          <p id="my-day-eyebrow" class="ta-eyebrow ta-num">
            {Dates.long(@today)}<span :if={@seq}> · {gettext("Séquence %{n}", n: @seq.number)}</span><span
              :if={@open?}
              class="hidden lg:inline"
            > · {deadline_text(@seq, @today)}</span>
          </p>
          <h1 class="text-2xl font-semibold leading-tight sm:text-[2rem]">
            {greeting(@current_scope.current_user)}
          </h1>
          <p :if={@lessons != []} class="text-[0.95rem] text-base-content/75">
            {subtitle(@lessons)}
          </p>
        </header>

        <div :if={@lessons == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={no_lessons_title(@day_off)} />
        </div>

        <div
          :if={@lessons != []}
          class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_24rem]"
        >
          <div class="flex min-w-0 flex-col gap-5">
            <RollCall.roll_panel
              :if={@roll}
              roll={@roll}
              title={roll_title(@roll, @selected_lesson, @labels)}
              eyebrow={roll_eyebrow(@selected_lesson)}
            >
              <:actions>
                <.link
                  :if={@roll.teaching_context}
                  id="roll-marks"
                  navigate={~p"/teacher/contexts/#{@roll.teaching_context.id}/marks"}
                  class="btn btn-ghost btn-sm btn-square"
                  aria-label={gettext("Saisir des notes")}
                  title={gettext("Saisir des notes")}
                >
                  <.icon name="hero-pencil-square" class="size-5" />
                </.link>
                <.link
                  id="close-roll"
                  patch={~p"/school/today"}
                  class="btn btn-ghost btn-sm btn-square"
                  aria-label={gettext("Fermer l'appel")}
                  title={gettext("Fermer l'appel")}
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </.link>
              </:actions>
            </RollCall.roll_panel>

            <.now_card :if={!@roll && @focus} lesson={@focus} labels={@labels} sizes={@sizes} />

            <div
              :if={!@roll && !@focus}
              id="now-card"
              class="ta-panel flex items-center gap-3 text-[0.95rem]"
            >
              <span class="grid size-10 shrink-0 place-items-center rounded-full bg-success/15 text-success">
                <.icon name="hero-check" class="size-5" />
              </span>
              <span>
                <span class="block font-semibold">{gettext("Journée terminée")}</span>
                <span class="text-sm text-base-content/70">
                  {gettext("Tous vos appels du jour sont faits.")}
                </span>
              </span>
            </div>

            <.sequence_panel :if={@seq && @courses != []} seq={@seq} courses={@courses} />
          </div>

          <div class="flex min-w-0 flex-col gap-4">
            <section id="today-slots" aria-label={gettext("Aujourd'hui")}>
              <h2 class="px-1 pb-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/70">
                {gettext("Aujourd'hui")}
              </h2>
              <ol class="ta-section flex flex-col">
                <.timeline_item
                  :for={item <- timeline(@lessons, @breaks)}
                  item={item}
                  selected={@selected}
                  labels={@labels}
                  sizes={@sizes}
                />
              </ol>
            </section>

            <.todo_card :if={@open? && @todo} seq={@seq} todo={@todo} today={@today} />

            <details
              :if={@missed != []}
              id="missed-this-week"
              class="ta-section group"
            >
              <summary class="flex min-h-14 cursor-pointer list-none items-center gap-3 px-4 py-3 [&::-webkit-details-marker]:hidden">
                <span class="ta-num grid size-7 shrink-0 place-items-center rounded-full bg-error/15 text-[0.8rem] font-semibold text-error">
                  {length(@missed)}
                </span>
                <span class="min-w-0 flex-1 text-[0.95rem] font-medium">
                  {ngettext(
                    "Appel manquant cette semaine",
                    "Appels manquants cette semaine",
                    length(@missed)
                  )}
                </span>
                <.icon
                  name="hero-chevron-down"
                  class="size-4 shrink-0 text-base-content/70 transition-transform group-open:rotate-180"
                />
              </summary>
              <ul class="border-t border-base-300">
                <li :for={m <- @missed}>
                  <.link
                    id={"missed-#{m.key}-#{m.date}"}
                    navigate={
                      ~p"/school/classes/#{hd(m.members).class_group.id}/attendance/#{m.period.id}?date=#{Date.to_iso8601(m.date)}"
                    }
                    class="ta-list-row"
                  >
                    <span class="flex min-w-0 flex-1 flex-col">
                      <span class="text-[0.92rem] font-medium leading-snug">
                        {LessonComponents.lesson_title(m, @labels)}
                      </span>
                      <span class="tabular-nums text-[0.75rem] text-base-content/70">
                        {Dates.short(m.date)} · {m.period.label} · {hm(m.period.start_time)}
                      </span>
                    </span>
                    <span class="shrink-0 text-sm font-semibold text-primary">
                      {gettext("Faire l'appel")}
                    </span>
                    <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/70" />
                  </.link>
                </li>
              </ul>
            </details>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # The hero's lesson: the one under way (its roll call taken or not), else the
  # next one, else the last one missed today.
  defp focus_lesson(lessons, time) do
    Enum.find(lessons, &under_way?(&1.period, time)) ||
      Enum.find(lessons, &(&1.status == :upcoming)) ||
      lessons |> Enum.filter(&(&1.status == :missed)) |> List.last()
  end

  defp under_way?(period, time),
    do:
      Time.compare(period.start_time, time) != :gt and Time.compare(time, period.end_time) == :lt

  # « clôture des notes le 9 déc. (J-36) »
  defp deadline_text(seq, today) do
    date = Dates.day_month(seq.grade_entry_deadline)

    case Dates.countdown(seq.grade_entry_deadline, today) do
      nil -> gettext("clôture des notes le %{date}", date: date)
      left -> gettext("clôture des notes le %{date} (%{left})", date: date, left: left)
    end
  end

  # The « À faire » figures: courses without an evaluation, courses in progress and
  # their marks; nil when nothing is left to enter.
  defp todo(courses) do
    none = Enum.count(courses, &(&1.progress.assessments == 0))

    started =
      Enum.filter(courses, fn %{progress: p} ->
        p.assessments > 0 and p.entered < p.expected
      end)

    if none + length(started) > 0 do
      %{
        none: none,
        started: length(started),
        entered: Enum.sum_by(started, & &1.progress.entered),
        expected: Enum.sum_by(started, & &1.progress.expected)
      }
    end
  end

  attr :seq, :map, required: true
  attr :todo, :map, required: true
  attr :today, :any, required: true

  # Phones: one row for the séquence's marks (from lg, the panel says it in full).
  defp todo_card(assigns) do
    ~H"""
    <section id="todo" aria-label={gettext("À faire")} class="flex flex-col gap-1.5 lg:hidden">
      <h2 class="px-1 text-xs font-semibold uppercase tracking-wide text-base-content/70">
        {gettext("À faire")}
      </h2>
      <.link
        id="todo-marks"
        navigate={~p"/school/courses?f=marks"}
        class="ta-panel flex items-center gap-3 transition-colors hover:border-base-content/30"
      >
        <.icon name="hero-pencil" class="size-5 shrink-0 text-warning" />
        <span class="flex min-w-0 flex-1 flex-col">
          <span class="text-[0.95rem] font-medium">
            {gettext("Notes de la séquence %{n}", n: @seq.number)}
          </span>
          <span class="text-[0.8rem] text-base-content/70">{todo_line(@todo)}</span>
        </span>
        <span
          :if={Dates.countdown(@seq.grade_entry_deadline, @today)}
          class="ta-num shrink-0 text-[0.8rem] font-semibold text-warning"
        >
          {Dates.countdown(@seq.grade_entry_deadline, @today)}
        </span>
      </.link>
    </section>
    """
  end

  # « 8 cours sans évaluation · 1 en cours (3/39) »
  defp todo_line(todo) do
    [
      todo.none > 0 &&
        ngettext("%{count} cours sans évaluation", "%{count} cours sans évaluation", todo.none),
      todo.started > 0 &&
        ngettext("%{count} en cours", "%{count} en cours", todo.started) <>
          " (#{todo.entered}/#{todo.expected})"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  attr :seq, :map, required: true
  attr :courses, :list, required: true

  # From lg: each course's entry in the séquence and its next step.
  defp sequence_panel(assigns) do
    ~H"""
    <section
      id="sequence-panel"
      aria-label={gettext("Notes de la séquence %{n}", n: @seq.number)}
      class="ta-panel hidden !p-0 lg:block"
    >
      <h2 class="px-4 pb-2 pt-3.5 text-base font-semibold">
        {gettext("Notes de la séquence %{n}", n: @seq.number)}
      </h2>
      <ul>
        <li :for={course <- @courses} id={"seq-course-#{course.id}"}>
          <.link
            navigate={~p"/teacher/contexts/#{course.context_id}/marks?seq=#{@seq.id}"}
            class="grid grid-cols-[minmax(0,11rem)_minmax(4rem,1fr)_minmax(0,9rem)_auto] items-center gap-4 border-t border-base-300/60 px-4 py-2.5 transition-colors hover:bg-base-content/5"
          >
            <span class="truncate text-sm font-semibold">{course.title}</span>
            <span class="h-1.5 overflow-hidden rounded-full bg-base-300/70" aria-hidden="true">
              <span
                class={["block h-full rounded-full", bar_tone(course.progress)]}
                style={"width: #{course.progress.pct || 0}%"}
              ></span>
            </span>
            <span class="ta-num truncate text-xs text-base-content/70">
              {course_state(course.progress)}
            </span>
            <span class="whitespace-nowrap text-sm font-semibold text-primary">
              {course_cta(course.progress)}
            </span>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  defp bar_tone(%{expected: x, entered: e}) when x > 0 and e >= x, do: "bg-primary"
  defp bar_tone(_progress), do: "bg-warning"

  defp course_state(%{assessments: 0}), do: gettext("Aucune évaluation")

  defp course_state(%{assessments: n, entered: e, expected: x}),
    do: ngettext("%{count} évaluation", "%{count} évaluations", n) <> " · #{e}/#{x}"

  defp course_cta(%{assessments: 0}), do: gettext("Créer une évaluation")
  defp course_cta(%{entered: e, expected: x}) when e < x, do: gettext("Continuer la saisie")
  defp course_cta(_progress), do: gettext("Voir les notes")

  attr :item, :any, required: true
  attr :selected, :string, default: nil
  attr :labels, :map, required: true
  attr :sizes, :map, required: true

  defp timeline_item(%{item: {:break, period}} = assigns) do
    assigns = assign(assigns, :period, period)

    ~H"""
    <li class="flex items-center gap-2 px-4 py-1.5" aria-hidden="true">
      <span class="h-px flex-1 bg-base-300"></span>
      <span class="tabular-nums text-[0.7rem] text-base-content/70">
        {@period.label} · {hm(@period.start_time)}
      </span>
      <span class="h-px flex-1 bg-base-300"></span>
    </li>
    """
  end

  defp timeline_item(%{item: {:lesson, lesson}} = assigns) do
    assigns = assign(assigns, :lesson, lesson)

    ~H"""
    <li class="border-t border-base-300/60 first:border-t-0">
      <.lesson_row
        id={"slot-#{@lesson.key}"}
        lesson={@lesson}
        selected={@selected == @lesson.key}
        labels={@labels}
        sizes={@sizes}
      />
    </li>
    """
  end

  # Lessons and the breaks that fall between the first and the last one, by start time.
  defp timeline([first | _] = lessons, breaks) do
    from = first.period.start_time
    to = List.last(lessons).period.start_time

    breaks =
      for b <- breaks,
          Time.compare(b.start_time, from) == :gt,
          Time.compare(b.start_time, to) == :lt,
          do: {:break, b}

    (Enum.map(lessons, &{:lesson, &1}) ++ breaks)
    |> Enum.sort_by(fn {_kind, x} -> start_time(x) end, Time)
  end

  defp start_time(%{period: p}), do: p.start_time
  defp start_time(%{start_time: t}), do: t

  attr :lesson, :map, required: true
  attr :labels, :map, required: true
  attr :sizes, :map, required: true

  defp now_card(assigns) do
    ~H"""
    <section
      id="now-card"
      aria-label={hero_eyebrow(@lesson.status)}
      class={[
        "ta-panel flex flex-col gap-3 !p-4 sm:!p-5 lg:flex-row lg:items-center lg:gap-5",
        hero_outline(@lesson.status)
      ]}
    >
      <div class="flex min-w-0 flex-1 flex-col gap-2">
        <div class="flex flex-wrap items-center gap-2">
          <span class={[
            "ta-num rounded-full px-2 py-[3px] text-[0.7rem] font-semibold uppercase tracking-wide",
            hero_pill(@lesson.status)
          ]}>
            {hero_eyebrow(@lesson.status)}
          </span>
          <span class="ta-num text-[0.85rem] text-base-content/70">
            {hm(@lesson.period.start_time)} – {hm(@lesson.period.end_time)} · {@lesson.period.label}
          </span>
        </div>
        <h2 class="text-[1.3rem] font-semibold leading-tight">
          {LessonComponents.lesson_title(@lesson, @labels)}
        </h2>
        <p class="text-[0.85rem] text-base-content/75">
          <span :if={LessonGroups.combined?(@lesson)}>{gettext("Cours groupé")} ·</span>
          {LessonComponents.lesson_sub(%{@lesson | hour: 1}, @sizes)}
          <span
            :if={LessonGroups.combined?(@lesson)}
            class="ta-num mt-1 block text-[0.78rem] font-medium"
          >
            {LessonComponents.classes_line(@lesson)}
          </span>
        </p>
        <p id="now-state" class={["text-[0.85rem]", state_tone(@lesson.status)]}>
          {hero_state(@lesson)}
        </p>
      </div>
      <div class="flex gap-2 lg:shrink-0">
        <.link
          :if={@lesson.status != :upcoming}
          id="now-call"
          patch={~p"/school/today?slot=#{@lesson.key}"}
          class={[
            "btn h-12 max-lg:flex-1",
            if(@lesson.status == :done, do: "btn-outline", else: "btn-primary")
          ]}
        >
          <.icon name="hero-clipboard-document-check" class="size-5" />
          {if @lesson.status == :done,
            do: gettext("Modifier l'appel"),
            else: gettext("Faire l'appel")}
        </.link>
        <.link
          :if={hd(@lesson.members).teaching_context_id}
          id="now-marks"
          navigate={~p"/teacher/contexts/#{hd(@lesson.members).teaching_context_id}/marks"}
          class="btn btn-outline h-12 border-base-300"
        >
          <.icon name="hero-pencil-square" class="size-5" />
          <span class="lg:hidden">{gettext("Notes")}</span>
          <span class="hidden lg:inline">{gettext("Saisir des notes")}</span>
        </.link>
      </div>
    </section>
    """
  end

  defp hero_eyebrow(:in_progress), do: gettext("Maintenant")
  defp hero_eyebrow(:upcoming), do: gettext("Prochain cours")
  defp hero_eyebrow(:missed), do: gettext("Appel non fait")
  defp hero_eyebrow(:done), do: gettext("Maintenant")
  defp hero_eyebrow(:on_paper), do: gettext("Sur feuille")
  defp hero_eyebrow(:not_held), do: gettext("Cours non assuré")

  defp hero_state(%{status: :done, absent: n}),
    do:
      gettext("Appel fait") <>
        " · " <> ngettext("%{count} absent", "%{count} absents", n)

  defp hero_state(%{status: :in_progress}), do: gettext("Appel à faire")
  defp hero_state(%{status: :missed}), do: gettext("Créneau terminé, appel non fait")
  defp hero_state(%{status: :on_paper}), do: gettext("Appel sur la feuille, à saisir")
  defp hero_state(%{status: :not_held}), do: gettext("Cours non assuré")

  defp hero_state(%{status: :upcoming, period: p}),
    do: gettext("L'appel s'ouvrira à %{time}", time: hm(p.start_time))

  # The lesson under way stands out with a solid outline; a missed one in coral.
  defp hero_outline(status) when status in [:in_progress, :done], do: "!border-2 !border-primary"
  defp hero_outline(:missed), do: "!border-2 !border-error"
  defp hero_outline(_status), do: nil

  defp hero_pill(status) when status in [:in_progress, :done],
    do: "bg-primary text-primary-content"

  defp hero_pill(:missed), do: "bg-error text-error-content"
  defp hero_pill(_status), do: "bg-base-200 text-base-content/75"

  defp state_tone(:done), do: "text-success"
  defp state_tone(:in_progress), do: "text-warning"
  defp state_tone(:missed), do: "text-error"

  defp state_tone(status) when status in [:upcoming, :on_paper, :not_held],
    do: "text-base-content/70"

  defp greeting(%User{} = user) do
    case User.display_name(user) do
      "" -> gettext("Ma journée")
      name -> gettext("Bonjour, %{name}", name: name)
    end
  end

  defp greeting(_user), do: gettext("Ma journée")

  defp subtitle(lessons) do
    to_call = Enum.count(lessons, &(&1.status in [:in_progress, :missed]))
    count = ngettext("%{count} cours aujourd'hui", "%{count} cours aujourd'hui", length(lessons))

    if to_call > 0,
      do:
        count <>
          " · " <>
          ngettext(
            "%{count} appel à faire maintenant",
            "%{count} appels à faire maintenant",
            to_call
          ),
      else: count
  end

  # « En cours · 10:00 – 10:55 » over the panel when its lesson is in progress, else
  # « Cours 2 · 08:55 – 09:50 ».
  defp roll_eyebrow(%{status: :in_progress, period: p}),
    do: gettext("En cours · %{from} – %{to}", from: hm(p.start_time), to: hm(p.end_time))

  defp roll_eyebrow(%{period: p}), do: "#{p.label} · #{hm(p.start_time)} – #{hm(p.end_time)}"
  defp roll_eyebrow(nil), do: nil

  defp roll_title(_roll, %{} = lesson, labels),
    do: gettext("Appel · %{what}", what: LessonComponents.lesson_title(lesson, labels))

  defp roll_title(roll, nil, _labels),
    do: gettext("Appel · %{what}", what: roll.cg.label)

  attr :id, :string, required: true
  attr :lesson, :map, required: true
  attr :selected, :boolean, required: true
  attr :labels, :map, required: true
  attr :sizes, :map, required: true

  # A lesson of the day: a link opening its roll call once it has started.
  defp lesson_row(assigns) do
    ~H"""
    <.link
      :if={@lesson.status != :upcoming}
      id={@id}
      patch={~p"/school/today?slot=#{@lesson.key}"}
      aria-current={@selected && "true"}
      class={[row_class(), @selected && "bg-primary/12", !@selected && "hover:bg-base-content/5"]}
    >
      <.lesson_cells lesson={@lesson} labels={@labels} sizes={@sizes} />
    </.link>
    <div :if={@lesson.status == :upcoming} id={@id} class={row_class()}>
      <.lesson_cells lesson={@lesson} labels={@labels} sizes={@sizes} />
    </div>
    """
  end

  defp row_class,
    do:
      "grid min-h-[3.25rem] grid-cols-[3rem_minmax(0,1fr)_auto] items-center gap-x-3 px-4 py-2 transition-colors"

  attr :lesson, :map, required: true
  attr :labels, :map, required: true
  attr :sizes, :map, required: true

  defp lesson_cells(assigns) do
    ~H"""
    <span class="ta-num text-[0.82rem] font-medium text-base-content/70">
      {hm(@lesson.period.start_time)}
    </span>
    <span class="flex min-w-0 flex-col">
      <span class={[
        "truncate text-[0.92rem] leading-snug",
        @lesson.status == :in_progress && "font-semibold",
        @lesson.status in [:done, :on_paper, :not_held] && "text-base-content/70"
      ]}>
        {LessonComponents.lesson_title(@lesson, @labels)}
      </span>
      <span class="truncate text-[0.72rem] text-base-content/70">
        {LessonComponents.lesson_sub(@lesson, @sizes)}
        <span :if={@lesson.status == :done}>
          · {ngettext("%{count} absent", "%{count} absents", @lesson.absent)}
        </span>
      </span>
    </span>
    <.status_tag status={@lesson.status} />
    """
  end
end
