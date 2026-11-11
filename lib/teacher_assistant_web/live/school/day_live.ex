defmodule TeacherAssistantWeb.School.DayLive do
  @moduledoc """
  Surveillant général → Aujourd'hui (spec G, V01–V04, V06; Vie scolaire redesign
  §2.1): today's roll calls as a classes × periods grid, the missed roll calls
  with « Relancer », and the school's latest sanctions. Absences are justified on
  `/school/absences`. The surveillant space's home.

  On phones (UX refonte 2026-11-03) the grid gives way to a hero card for the lesson
  under way (calls done, on paper, absents, one action) and the day's lessons, each
  with its progress and state, opening onto its classes. Typing a whole lesson's paper
  sheets at once is deferred: the action opens a class's roll sheet.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.School.SchoolLifeComponents, only: [hm: 1, teacher_name: 1]

  alias TeacherAssistant.{Attendance, Discipline}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.{Authz, Dates, SanctionLabels}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Discipline.can_manage_conduct?(scope) do
      socket =
        assign(socket, page_title: gettext("Aujourd'hui"), loading?: not connected?(socket))

      # A8: the day's reads run once, on the connected render.
      {:ok, if(socket.assigns.loading?, do: socket, else: load(socket))}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    today = Reference.today()
    now = Reference.now()

    counts = Attendance.absence_counts(scope, today)

    assign(socket,
      today: today,
      now: now,
      day: Attendance.school_day(scope, today, now),
      reminded: Attendance.reminded_slot_ids(scope, today),
      day_off: Attendance.day_off(scope, today),
      absent_students: counts.today_absent_students,
      to_justify: counts.to_justify,
      lates: Attendance.late_count(scope, today),
      sanctions: Enum.take(Discipline.recent_sanctions!(scope: scope), 3),
      missed_shown: 5
    )
  end

  def handle_event("remind", %{"slot" => slot_id}, socket) do
    scope = socket.assigns.current_scope
    # « Relancer » on a missed lesson or one waiting for its paper sheet (spec 2026-10-28).
    missed =
      Enum.find(
        socket.assigns.day.missed ++ on_paper(socket.assigns.day),
        &(&1.slot_id == slot_id)
      )

    case missed && Attendance.remind_roll_call(scope, slot_id, socket.assigns.today) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Rappel envoyé à %{teacher}.", teacher: teacher_name(missed.teacher))
         )
         |> load()}

      {:error, :already_reminded} ->
        {:noreply, load(socket)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  defp no_lessons_title({:holiday, label}), do: gettext("Jour férié : %{label}", label: label)
  defp no_lessons_title(_), do: gettext("Pas de cours aujourd'hui")

  # Lessons waiting for their class's paper sheet, in grid order.
  defp on_paper(day) do
    for row <- day.rows,
        {_id, cell} <- Enum.sort_by(row.cells, fn {_id, c} -> c.period.position end),
        cell.status == :on_paper,
        do: cell
  end

  def render(%{loading?: true} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.page_header title={@page_title} />
      <.loading_panel id="day-loading" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        current: current_period(assigns.day.periods, assigns.now),
        tally: tally(assigns.day),
        on_paper: on_paper(assigns.day)
      )

    periods = period_rows(assigns.day, assigns.current)
    assigns = assign(assigns, periods: periods, hero: hero_period(periods))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-day" class="grid items-start gap-5 lg:grid-cols-2">
        <div class="lg:col-span-2">
          <.page_header
            eyebrow={
              gettext("%{date} · %{time}",
                date: Dates.long(@today),
                time: Calendar.strftime(@now, "%H:%M")
              )
            }
            title={gettext("Aujourd'hui")}
          >
            <:actions>
              <.link
                id="print-all-sheets"
                href={~p"/school/roll-sheets/print"}
                target="_blank"
                class="btn btn-ghost btn-sm min-h-11 sm:min-h-0"
              >
                <.icon name="hero-printer" class="size-4" />
                {gettext("Imprimer toutes les feuilles")}
              </.link>
              <.link
                id="to-absences"
                navigate={~p"/school/absences"}
                class="btn btn-outline btn-sm min-h-11 sm:min-h-0"
              >
                {gettext("Absences à justifier · %{count}", count: @to_justify)}
              </.link>
            </:actions>
          </.page_header>
        </div>

        <.period_hero :if={@day.rows != []} hero={@hero} tally={@tally} today={@today} />

        <p
          :if={@day.rows != []}
          id="calls-summary"
          class={[
            "flex items-center gap-2 text-[0.95rem] font-semibold lg:col-span-2",
            summary_tone(@tally)
          ]}
        >
          <.icon name={summary_icon(@tally)} class="size-5 shrink-0" />
          <span>{summary_text(@tally)}</span>
        </p>

        <div class="grid grid-cols-2 gap-2.5 lg:col-span-2 lg:grid-cols-4">
          <.kpi
            id="kpi-calls"
            label={gettext("Appels faits")}
            value={"#{@tally.done} / #{@tally.done + @tally.missed + @tally.on_paper}"}
            sub={
              ngettext(
                "%{count} non fait à %{time}",
                "%{count} non faits à %{time}",
                @tally.missed,
                time: Calendar.strftime(@now, "%H:%M")
              ) <>
                if(@tally.on_paper > 0,
                  do: " · " <> gettext("%{count} sur feuille", count: @tally.on_paper),
                  else: ""
                )
            }
            tone={if @tally.missed == 0, do: "text-success", else: "text-base-content"}
          />
          <.kpi
            id="kpi-absents"
            label={gettext("Absents")}
            value={to_string(@absent_students)}
            sub={gettext("élèves sur au moins un créneau")}
          />
          <.kpi
            id="kpi-lates"
            label={gettext("Retards")}
            value={to_string(@lates)}
            sub={first_period_text(@day.periods)}
            tone={if @lates > 0, do: "text-warning", else: "text-base-content"}
          />
          <.kpi
            id="kpi-to-justify"
            label={gettext("À justifier")}
            value={to_string(@to_justify)}
            sub={gettext("sur la séquence en cours")}
            tone={if @to_justify > 0, do: "text-error", else: "text-base-content"}
          />
        </div>

        <div :if={@day.rows == []} id="no-lessons" class="lg:col-span-2">
          <.empty_state icon="hero-sun" title={no_lessons_title(@day_off)} />
        </div>

        <section
          :if={@day.rows != []}
          id="class-calls"
          class="ta-section max-sm:order-1 lg:col-span-2"
        >
          <header class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 pb-2 pt-4">
            <h2 class="text-base font-semibold">
              <span class="sm:hidden">{gettext("Créneaux du jour")}</span>
              <span class="max-sm:hidden">{gettext("Appels par créneau · nombre d'absents")}</span>
            </h2>
            <div
              id="grid-legend"
              class="flex flex-wrap gap-x-3 gap-y-1 text-[0.75rem] text-base-content/75 max-sm:hidden"
            >
              <span
                :for={status <- [:done, :in_progress, :missed, :on_paper, :not_held, :upcoming]}
                class="flex items-center gap-1.5"
              >
                <span class={[
                  "ta-num grid h-4 min-w-4 place-items-center rounded-[0.2rem] border px-0.5 text-[0.65rem] font-semibold leading-none",
                  cell_class(%{status: status})
                ]}>
                  {legend_glyph(status)}
                </span>
                {legend_label(status)}
              </span>
            </div>
          </header>

          <div class="overflow-x-auto px-4 pb-4 max-sm:hidden">
            <div
              id="roll-call-grid"
              class="grid gap-[3px]"
              style={"grid-template-columns: 62px repeat(#{length(@day.periods)}, minmax(54px, 1fr)); min-width: #{62 + length(@day.periods) * 57}px"}
            >
              <span></span>
              <span
                :for={p <- @day.periods}
                class={[
                  "ta-num flex flex-col items-center py-[3px] text-[0.66rem] font-semibold",
                  if(@current && @current.id == p.id,
                    do: "text-warning",
                    else: "text-base-content/75"
                  )
                ]}
              >
                <span class="truncate">{p.label}</span>
                <span class="font-normal">{hm(p.start_time)}</span>
              </span>
              <%= for row <- @day.rows do %>
                <span
                  id={"grid-#{row.class_group.id}"}
                  class="flex items-center truncate text-[0.82rem] font-semibold"
                >
                  <.link
                    :if={row.class_group.paper_roll_call}
                    navigate={~p"/school/classes/#{row.class_group.id}/roll-sheet"}
                    title={gettext("Saisir la feuille")}
                    class="truncate hover:underline"
                  >
                    {row.class_group.label}
                  </.link>
                  <span :if={!row.class_group.paper_roll_call} class="truncate">
                    {row.class_group.label}
                  </span>
                </span>
                <.grid_cell :for={p <- @day.periods} cell={row.cells[p.id]} today={@today} />
              <% end %>
            </div>
          </div>

          <ul id="day-periods" class="border-t border-base-300 sm:hidden">
            <li :for={row <- @periods}>
              <.period_row row={row} today={@today} />
            </li>
          </ul>
        </section>

        <section id="missed-roll-calls" class="ta-section">
          <header class="flex items-baseline justify-between gap-2 px-4 pb-2 pt-4">
            <h2 class="text-base font-semibold">{gettext("Appels non faits")}</h2>
            <span :if={@day.missed != []} class="ta-num text-[0.8rem] font-semibold text-error">
              {length(@day.missed)}
            </span>
          </header>
          <p :if={@day.missed == []} class="px-4 pb-4 text-sm text-base-content/70">
            {gettext("Tous les appels passés sont faits.")}
          </p>
          <ul :if={@day.missed != []} class="border-t border-base-300">
            <li :for={m <- Enum.take(@day.missed, @missed_shown)}>
              <.missed_row m={m} reminded={@reminded} />
            </li>
          </ul>
          <details :if={length(@day.missed) > @missed_shown} class="group border-t border-base-300">
            <summary class="flex min-h-11 cursor-pointer list-none items-center justify-center gap-1 px-4 py-2 text-sm font-semibold text-primary [&::-webkit-details-marker]:hidden">
              <span class="group-open:hidden">
                {gettext("Voir les %{count}", count: length(@day.missed))}
              </span>
              <span class="hidden group-open:inline">{gettext("Réduire")}</span>
              <.icon name="hero-chevron-down" class="size-4 group-open:rotate-180" />
            </summary>
            <ul class="border-t border-base-300">
              <li :for={m <- Enum.drop(@day.missed, @missed_shown)}>
                <.missed_row m={m} reminded={@reminded} />
              </li>
            </ul>
          </details>
        </section>

        <section :if={@on_paper != []} id="paper-roll-calls" class="ta-section">
          <header class="flex items-baseline justify-between gap-2 px-4 pb-2 pt-4">
            <h2 class="text-base font-semibold">{gettext("Sur feuille · à saisir")}</h2>
            <span class="ta-num text-[0.8rem] font-semibold text-base-content/70">
              {length(@on_paper)}
            </span>
          </header>
          <ul class="border-t border-base-300">
            <li :for={m <- Enum.take(@on_paper, @missed_shown)}>
              <.missed_row m={m} reminded={@reminded} id_prefix="paper" />
            </li>
          </ul>
          <details :if={length(@on_paper) > @missed_shown} class="group border-t border-base-300">
            <summary class="flex min-h-11 cursor-pointer list-none items-center justify-center gap-1 px-4 py-2 text-sm font-semibold text-primary [&::-webkit-details-marker]:hidden">
              <span class="group-open:hidden">
                {gettext("Voir les %{count}", count: length(@on_paper))}
              </span>
              <span class="hidden group-open:inline">{gettext("Réduire")}</span>
              <.icon name="hero-chevron-down" class="size-4 group-open:rotate-180" />
            </summary>
            <ul class="border-t border-base-300">
              <li :for={m <- Enum.drop(@on_paper, @missed_shown)}>
                <.missed_row m={m} reminded={@reminded} id_prefix="paper" />
              </li>
            </ul>
          </details>
        </section>

        <section id="recent-sanctions" class="ta-section max-sm:order-2">
          <header class="flex items-baseline justify-between gap-2 px-4 pb-2 pt-4">
            <h2 class="text-base font-semibold">{gettext("Sanctions récentes")}</h2>
            <.link
              id="all-sanctions"
              navigate={~p"/school/sanctions"}
              class="text-[0.85rem] font-semibold text-info hover:underline"
            >
              {gettext("Toutes →")}
            </.link>
          </header>
          <p :if={@sanctions == []} class="px-4 pb-4 text-sm text-base-content/70">
            {gettext("Aucune sanction")}
          </p>
          <ul :if={@sanctions != []} class="border-t border-base-300">
            <li :for={s <- @sanctions}>
              <.link
                id={"sanction-#{s.id}"}
                navigate={~p"/school/classes/#{s.enrollment.class_group_id}/discipline"}
                class="ta-list-row"
              >
                <span class="flex min-w-0 flex-1 flex-col">
                  <span class="text-[0.92rem] font-medium leading-snug">
                    {s.enrollment.student.full_name} · {s.enrollment.class_group.label}
                  </span>
                  <span class="text-[0.78rem] text-base-content/70">
                    {sanction_text(s)} ·
                    <b :if={is_nil(s.parents_notified_on)} class="text-warning">
                      {gettext("parents à notifier")}
                    </b>
                    <span :if={s.parents_notified_on}>
                      {notified_text(s.parents_notified_on, @today)}
                    </span>
                  </span>
                </span>
                <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/70" />
              </.link>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :m, :map, required: true
  attr :reminded, :any, required: true
  attr :id_prefix, :string, default: "missed"

  defp missed_row(assigns) do
    ~H"""
    <div id={"#{@id_prefix}-#{@m.class_group.id}-#{@m.period.id}"} class="ta-list-row">
      <div class="flex min-w-0 flex-1 flex-col">
        <span class="text-[0.92rem] font-medium leading-snug">
          {@m.class_group.label} · <span class="ta-num">{hm(@m.period.start_time)}</span>
          · {@m.subject}
        </span>
        <span class="text-[0.78rem] text-base-content/70">
          {teacher_name(@m.teacher)} · {if @m.status == :on_paper,
            do: gettext("sur feuille · à saisir"),
            else: gettext("créneau terminé")}
        </span>
      </div>
      <span
        :if={MapSet.member?(@reminded, @m.slot_id)}
        id={"reminded-#{@m.slot_id}"}
        class="flex flex-none items-center gap-1 text-[0.8rem] font-semibold text-success"
      >
        {gettext("Relancé ✓")}
      </span>
      <button
        :if={not MapSet.member?(@reminded, @m.slot_id)}
        id={"remind-#{@m.slot_id}"}
        type="button"
        class="btn btn-outline btn-sm min-h-11 flex-none sm:min-h-0"
        phx-click="remind"
        phx-value-slot={@m.slot_id}
        phx-disable-with={gettext("Envoi…")}
      >
        {gettext("Relancer")}
      </button>
    </div>
    """
  end

  attr :hero, :map, default: nil
  attr :tally, :map, required: true
  attr :today, :any, required: true

  # Phone: the lesson under way (else the next one), its three figures and one action.
  defp period_hero(%{hero: nil} = assigns) do
    ~H"""
    <section id="period-hero" class="ta-section flex flex-col gap-1 p-4 sm:hidden">
      <span class="ta-eyebrow">{gettext("Journée terminée")}</span>
      <span class="ta-num text-lg font-semibold">
        {ngettext("%{count} appel fait", "%{count} appels faits", @tally.done)} / {@tally.done +
          @tally.missed + @tally.on_paper}
      </span>
    </section>
    """
  end

  defp period_hero(assigns) do
    assigns = assign(assigns, :paper, first_paper(assigns.hero))

    ~H"""
    <section
      id="period-hero"
      aria-label={gettext("Créneau en cours")}
      class={[
        "flex flex-col gap-3 rounded-box border-2 bg-base-100 p-4 sm:hidden",
        if(@hero.state == :current, do: "border-primary", else: "border-base-300")
      ]}
    >
      <div class="flex items-center gap-2">
        <span class={[
          "ta-num rounded-full px-2 py-0.5 text-[0.7rem] font-semibold uppercase",
          if(@hero.state == :current,
            do: "bg-primary text-primary-content",
            else: "bg-base-200 text-base-content/75"
          )
        ]}>
          {if @hero.state == :current, do: gettext("En cours"), else: gettext("Prochain")} · {@hero.period.label}
        </span>
        <span class="ta-num text-sm text-base-content/70">
          {hm(@hero.period.start_time)} – {hm(@hero.period.end_time)}
        </span>
      </div>
      <div class="grid grid-cols-3 gap-2 text-center">
        <div>
          <p class="ta-num text-[1.4rem] font-semibold leading-tight">{@hero.done}</p>
          <p class="text-[0.72rem] text-base-content/70">
            {ngettext("appel fait", "appels faits", @hero.done)}
          </p>
        </div>
        <div>
          <p class={[
            "ta-num text-[1.4rem] font-semibold leading-tight",
            @hero.on_paper > 0 && "text-warning"
          ]}>
            {@hero.on_paper}
          </p>
          <p class="text-[0.72rem] text-base-content/70">{gettext("sur feuille")}</p>
        </div>
        <div>
          <p class={[
            "ta-num text-[1.4rem] font-semibold leading-tight",
            @hero.absent > 0 && "text-error"
          ]}>
            {@hero.absent}
          </p>
          <p class="text-[0.72rem] text-base-content/70">
            {ngettext("absent", "absents", @hero.absent)}
          </p>
        </div>
      </div>
      <.link
        :if={@paper}
        id="hero-action"
        navigate={~p"/school/classes/#{@paper.class_group.id}/roll-sheet"}
        class="btn btn-primary min-h-12"
      >
        {gettext("Saisir la feuille d'appel · %{class}", class: @paper.class_group.label)}
      </.link>
      <a
        :if={!@paper && @hero.missed > 0}
        id="hero-action"
        href="#missed-roll-calls"
        class="btn btn-primary min-h-12"
      >
        {ngettext("Relancer l'appel non fait", "Relancer les %{count} appels non faits", @hero.missed)}
      </a>
      <p
        :if={!@paper && @hero.missed == 0}
        class="text-center text-sm text-base-content/70"
      >
        {hero_note(@hero)}
      </p>
    </section>
    """
  end

  attr :row, :map, required: true
  attr :today, :any, required: true

  # Phone: one lesson of the day — its progress and state, opening onto its classes.
  defp period_row(assigns) do
    ~H"""
    <details id={"period-#{@row.period.id}"} class="group border-b border-base-300 last:border-b-0">
      <summary class="flex min-h-14 cursor-pointer list-none items-center gap-3 px-4 py-2 [&::-webkit-details-marker]:hidden">
        <span class="flex w-16 shrink-0 flex-col">
          <span class="truncate text-[0.88rem] font-semibold">{@row.period.label}</span>
          <span class="ta-num text-[0.72rem] text-base-content/70">{hm(@row.period.start_time)}</span>
        </span>
        <span class="h-1.5 flex-1 overflow-hidden rounded-full bg-base-300/70">
          <span
            class={["block h-full rounded-full", period_bar(@row.state)]}
            style={"width: #{period_pct(@row)}%"}
          ></span>
        </span>
        <span class={[
          "ta-num w-28 shrink-0 text-right text-[0.76rem] font-medium",
          period_tone(@row.state)
        ]}>
          {period_state_text(@row)}
        </span>
        <.icon
          name="hero-chevron-down"
          class="size-4 shrink-0 text-base-content/60 transition-transform group-open:rotate-180"
        />
      </summary>
      <ul class="pb-2">
        <li :for={cell <- @row.cells}>
          <.period_class cell={cell} today={@today} />
        </li>
      </ul>
    </details>
    """
  end

  attr :cell, :map, required: true
  attr :today, :any, required: true

  defp period_class(%{cell: %{status: status}} = assigns) when status in [:upcoming, :not_held] do
    ~H"""
    <div class="flex min-h-11 items-center gap-3 px-4 text-sm text-base-content/70">
      <span class="flex-1 truncate">{@cell.class_group.label} · {@cell.subject}</span>
      <span class="text-xs">{cell_state_text(@cell)}</span>
    </div>
    """
  end

  defp period_class(assigns) do
    ~H"""
    <.link
      id={"period-class-#{@cell.class_group.id}-#{@cell.period.id}"}
      navigate={period_class_path(@cell, @today)}
      class="flex min-h-11 items-center gap-3 px-4 text-sm hover:bg-base-200/60 hover:no-underline"
    >
      <span class="flex-1 truncate">
        <span class="font-medium">{@cell.class_group.label}</span>
        <span class="text-base-content/70">· {@cell.subject}</span>
      </span>
      <span class={["ta-num rounded-[0.3rem] border px-1.5 text-xs font-semibold", cell_class(@cell)]}>
        {cell_state_text(@cell)}
      </span>
      <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/60" />
    </.link>
    """
  end

  # A paper lesson opens its class's sheet, any other its roll call.
  defp period_class_path(%{status: :on_paper} = cell, _today),
    do: ~p"/school/classes/#{cell.class_group.id}/roll-sheet"

  defp period_class_path(cell, today),
    do:
      ~p"/school/classes/#{cell.class_group.id}/attendance/#{cell.period.id}?date=#{Date.to_iso8601(today)}"

  defp cell_state_text(%{status: :done, absent: n}),
    do: ngettext("%{count} absent", "%{count} absents", n)

  defp cell_state_text(%{status: :missed}), do: gettext("Appel non fait")
  defp cell_state_text(%{status: :in_progress}), do: gettext("En cours")
  defp cell_state_text(%{status: :upcoming}), do: gettext("À venir")
  defp cell_state_text(%{status: :on_paper}), do: gettext("Sur feuille")
  defp cell_state_text(%{status: :not_held}), do: gettext("Non assuré")

  # The day's lessons with at least one class, each with its tally and state:
  # `:current` (under way), `:upcoming`, `:complete` (every call in) or `:behind`.
  defp period_rows(day, current) do
    for p <- day.periods,
        cells =
          day.rows
          |> Enum.map(& &1.cells[p.id])
          |> Enum.reject(&is_nil/1),
        cells != [] do
      counted = Enum.reject(cells, &(&1.status == :not_held))
      freq = Enum.frequencies_by(counted, & &1.status)
      count = &Map.get(freq, &1, 0)

      row = %{
        period: p,
        cells: cells,
        total: length(counted),
        done: count.(:done),
        missed: count.(:missed),
        on_paper: count.(:on_paper),
        in_progress: count.(:in_progress),
        upcoming: count.(:upcoming),
        absent: for(%{status: :done, absent: n} <- counted, reduce: 0, do: (acc -> acc + n))
      }

      Map.put(row, :state, period_state(row, current))
    end
  end

  defp period_state(%{period: %{id: id}}, %{id: id}), do: :current
  defp period_state(%{total: n, upcoming: n}, _current) when n > 0, do: :upcoming
  defp period_state(%{missed: 0, on_paper: 0, in_progress: 0}, _current), do: :complete
  defp period_state(_row, _current), do: :behind

  defp hero_period(rows),
    do: Enum.find(rows, &(&1.state == :current)) || Enum.find(rows, &(&1.state == :upcoming))

  defp first_paper(hero), do: Enum.find(hero.cells, &(&1.status == :on_paper))

  defp hero_note(%{state: :upcoming}), do: gettext("Les appels s'ouvrent au début du cours.")
  defp hero_note(%{in_progress: n}) when n > 0, do: gettext("Les enseignants font l'appel.")
  defp hero_note(_hero), do: gettext("Tous les appels de ce cours sont faits.")

  defp period_pct(%{total: 0}), do: 0
  defp period_pct(%{done: done, total: total}), do: div(done * 100, total)

  defp period_bar(:complete), do: "bg-success"
  defp period_bar(:current), do: "bg-primary"
  defp period_bar(:behind), do: "bg-warning"
  defp period_bar(:upcoming), do: "bg-base-content/20"

  defp period_tone(:complete), do: "text-base-content/70"
  defp period_tone(:current), do: "text-primary"
  defp period_tone(:behind), do: "text-warning"
  defp period_tone(:upcoming), do: "text-base-content/70"

  defp period_state_text(%{state: :current} = row),
    do: gettext("en cours · %{done}/%{total}", done: row.done, total: row.total)

  defp period_state_text(%{state: :upcoming}), do: gettext("à venir")

  defp period_state_text(%{state: :complete} = row),
    do:
      "#{row.done}/#{row.total} · " <>
        ngettext("%{count} abs.", "%{count} abs.", row.absent)

  defp period_state_text(row),
    do: gettext("%{done}/%{total} à jour", done: row.done, total: row.total)

  attr :cell, :map, default: nil
  attr :today, :any, required: true

  defp grid_cell(%{cell: nil} = assigns),
    do:
      ~H|<span class="ta-num grid h-[30px] place-items-center text-[0.76rem] text-base-content/35">·</span>|

  # Upcoming lessons are not links: their roll call cannot be taken yet.
  defp grid_cell(%{cell: %{status: :upcoming}} = assigns) do
    ~H"""
    <span
      title={cell_title(@cell)}
      class={["grid h-[30px] place-items-center rounded-[0.35rem] border", cell_class(@cell)]}
    ></span>
    """
  end

  defp grid_cell(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/school/classes/#{@cell.class_group.id}/attendance/#{@cell.period.id}?date=#{Date.to_iso8601(@today)}"
      }
      title={cell_title(@cell)}
      aria-label={cell_title(@cell)}
      class={[
        "ta-num grid h-[30px] place-items-center rounded-[0.35rem] border text-[0.76rem] font-semibold transition-opacity hover:opacity-80",
        cell_class(@cell)
      ]}
    >
      {cell_text(@cell)}
    </.link>
    """
  end

  # Colour by what the cell means now: done (success, with its absent count), in
  # progress without a roll call (warning), finished without one (error), not
  # started yet (neutral).
  defp cell_class(%{status: :done}), do: "border-success/30 bg-success/12 text-success"
  defp cell_class(%{status: :missed}), do: "border-error/45 bg-error/15 text-error"
  defp cell_class(%{status: :in_progress}), do: "border-warning/60 bg-warning/12 text-warning"
  defp cell_class(%{status: :upcoming}), do: "border-dashed border-base-content/25"
  # Spec 2026-10-28: waiting for the paper sheet (neutral), or not held (muted).
  defp cell_class(%{status: :on_paper}),
    do: "border-base-content/20 bg-base-200 text-base-content/70"

  defp cell_class(%{status: :not_held}),
    do: "border-dashed border-base-content/20 bg-base-200/40 text-base-content/50"

  defp cell_text(%{status: :done, absent: n}), do: n
  defp cell_text(%{status: :missed}), do: "!"
  defp cell_text(%{status: :in_progress}), do: "…"
  defp cell_text(%{status: :upcoming}), do: ""
  defp cell_text(%{status: :on_paper}), do: "✎"
  defp cell_text(%{status: :not_held}), do: "—"

  # what a cell of that status shows, so the legend reads like the grid
  defp legend_glyph(:done), do: "2"
  defp legend_glyph(status), do: cell_text(%{status: status})

  defp legend_label(:done), do: gettext("Fait (nb d'absents)")
  defp legend_label(:in_progress), do: gettext("En cours")
  defp legend_label(:missed), do: gettext("Appel non fait")
  defp legend_label(:upcoming), do: gettext("À venir")
  defp legend_label(:on_paper), do: gettext("Sur feuille")
  defp legend_label(:not_held), do: gettext("Non assuré")

  defp cell_title(%{status: :done, absent: n} = cell),
    do: "#{ngettext("%{count} absent", "%{count} absents", n)} · #{cell_detail(cell)}"

  defp cell_title(%{status: :missed} = cell),
    do: "#{gettext("Appel non fait")} · #{cell_detail(cell)}"

  defp cell_title(%{status: :in_progress} = cell),
    do: "#{gettext("En cours")} · #{cell_detail(cell)}"

  defp cell_title(%{status: :upcoming} = cell), do: "#{gettext("À venir")} · #{cell_detail(cell)}"

  defp cell_title(%{status: :on_paper} = cell),
    do: "#{gettext("sur feuille · à saisir")} · #{cell_detail(cell)}"

  defp cell_title(%{status: :not_held} = cell),
    do: "#{gettext("Cours non assuré")} · #{cell_detail(cell)}"

  defp cell_detail(cell), do: "#{cell.subject} · #{teacher_name(cell.teacher)}"

  # Today's roll calls by state.
  defp tally(day) do
    statuses = for row <- day.rows, {_id, cell} <- row.cells, do: cell.status
    freq = Enum.frequencies(statuses)

    %{
      done: Map.get(freq, :done, 0),
      missed: Map.get(freq, :missed, 0),
      in_progress: Map.get(freq, :in_progress, 0),
      upcoming: Map.get(freq, :upcoming, 0),
      on_paper: Map.get(freq, :on_paper, 0)
    }
  end

  defp summary_text(%{missed: 0, in_progress: 0, on_paper: n}) when n > 0,
    do:
      ngettext("%{count} appel sur feuille, à saisir", "%{count} appels sur feuille, à saisir", n)

  defp summary_text(%{missed: 0, in_progress: 0, upcoming: 0}),
    do: gettext("Tous les appels sont faits")

  defp summary_text(%{missed: 0, in_progress: n}) when n > 0,
    do: ngettext("%{count} appel en cours", "%{count} appels en cours", n)

  defp summary_text(%{missed: 0}), do: gettext("Aucun appel manquant pour l'instant")

  defp summary_text(%{missed: n}),
    do:
      ngettext("%{count} appel manquant aujourd'hui", "%{count} appels manquants aujourd'hui", n)

  defp summary_tone(%{missed: n}) when n > 0, do: "text-error"
  defp summary_tone(%{in_progress: n}) when n > 0, do: "text-warning"
  defp summary_tone(%{on_paper: n}) when n > 0, do: "text-base-content/75"
  defp summary_tone(_tally), do: "text-success"

  defp summary_icon(%{missed: n}) when n > 0, do: "hero-exclamation-circle"
  defp summary_icon(%{in_progress: n}) when n > 0, do: "hero-clock"
  defp summary_icon(%{on_paper: n}) when n > 0, do: "hero-document-text"
  defp summary_icon(_tally), do: "hero-check-circle"

  defp current_period(periods, now) do
    time = NaiveDateTime.to_time(now)

    Enum.find(periods, fn p ->
      Time.compare(p.start_time, time) != :gt and Time.compare(time, p.end_time) == :lt
    end)
  end

  # « depuis 07:30 »: the school's first lesson.
  defp first_period_text([]), do: nil
  defp first_period_text([first | _]), do: gettext("depuis %{time}", time: hm(first.start_time))

  defp sanction_text(s) do
    [SanctionLabels.sanction_label(s), s.reason]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp notified_text(date, today) do
    case Date.diff(today, date) do
      0 -> gettext("parents notifiés aujourd'hui")
      1 -> gettext("parents notifiés hier")
      _ -> gettext("parents notifiés le %{date}", date: Dates.short(date))
    end
  end
end
