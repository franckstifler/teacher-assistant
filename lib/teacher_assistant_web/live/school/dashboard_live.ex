defmodule TeacherAssistantWeb.School.DashboardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{
    Accounts,
    Assessment,
    Attendance,
    Curriculum,
    Enrollment,
    Organization,
    Pilotage,
    Scope
  }

  alias TeacherAssistant.Academics.{Reference, SchoolTemplates}
  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope.current_workspace != nil and landing_elsewhere(scope) != nil ->
        {:ok, push_navigate(socket, to: landing_elsewhere(scope))}

      # A8: the dashboard's reads run once, on the connected render.
      scope.current_workspace != nil and not connected?(socket) ->
        {:ok, assign(socket, page_title: gettext("Dashboard"), loading?: true)}

      scope.current_workspace != nil ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Dashboard"))
         |> assign(:loading?, false)
         |> assign(:scope, scope)
         |> load_dashboard()}

      true ->
        # A stale workspace id (or a deactivated membership) can leave the
        # resolved scope without a workspace even though the user has a real
        # school — send them there instead of prompting to create a new one.
        case Organization.list_workspaces_for(%TeacherAssistant.Scope{
               current_user: scope.current_user
             }) do
          [first | _] -> {:ok, assign(socket, :open_school_id, first.id)}
          [] -> {:ok, push_navigate(socket, to: ~p"/schools/new")}
        end
    end
  end

  # The Proviseur uses the dashboard as its home; every other space lands on its
  # own home (spec E; the Censeur on sequence tracking, spec F).
  defp landing_elsewhere(%{capabilities: %{space: %{key: key}}})
       when key == :proviseur,
       do: nil

  defp landing_elsewhere(%{capabilities: %{space: %{home: home}}}), do: home
  defp landing_elsewhere(_scope), do: nil

  def render(%{loading?: true} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.page_header title={@page_title} />
      <.loading_panel id="dashboard-loading" />
    </Layouts.app>
    """
  end

  def render(%{open_school_id: _} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <p id="opening-school" class="ta-text-2 py-10 text-center">
        {gettext("Ouverture de votre établissement…")}
      </p>
      <Layouts.open_school_form :if={connected?(@socket)} school_id={@open_school_id} />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="dashboard" class="flex flex-col gap-5">
        <.page_header eyebrow={eyebrow(@today, @sequence)} title={gettext("Tableau de bord")} />

        <%!-- Verification gate callout — real school_verification_status --%>
        <div
          :if={@current_scope.school_verification_status != :verified}
          id="pending-verification"
          class="ta-leaf flex gap-3 border-l-4 border-warning"
        >
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
          <p class="text-sm leading-relaxed text-base-content/80">
            {gettext(
              "Votre établissement est configuré mais pas encore vérifié. Vous pouvez préparer classes et personnel ; la saisie des notes, de l'appel et des bulletins sera débloquée après vérification."
            )}
          </p>
        </div>

        <%!-- Onboarding checklist, only while setup is incomplete or unverified --%>
        <div :if={@show_setup?} id="setup-checklist" class="ta-leaf space-y-2">
          <h2 class="ta-eyebrow">{gettext("Mise en route")}</h2>
          <ul class="divide-y divide-base-300/70 text-sm">
            <.check_item id="setup-checklist-profile" done?={@profile_complete?}>
              {gettext("Profil de l'établissement")}
            </.check_item>
            <.check_item id="setup-checklist-year" done?={@year != nil}>
              {gettext("Année scolaire")}
            </.check_item>
            <.check_item id="setup-checklist-classes" done?={@setup_complete?}>
              {gettext("Classes")}
            </.check_item>
            <.check_item id="setup-checklist-staff" done?={@staff_count > 1}>
              {gettext("Personnel")}
            </.check_item>
          </ul>
        </div>

        <section
          :if={@setup_steps != []}
          id="setup-steps"
          aria-labelledby="setup-steps-title"
          class="flex flex-col gap-3 rounded-box border border-warning/45 bg-base-200/40 p-4 sm:p-5"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
            <h2 id="setup-steps-title" class="text-base font-semibold">
              {ngettext(
                "Mise en place de l'année · %{count} étape restante",
                "Mise en place de l'année · %{count} étapes restantes",
                length(@setup_steps)
              )}
            </h2>
            <span
              :if={@todo.classes_without_pp != []}
              class="ta-num text-xs text-base-content/70"
            >
              {gettext("bloque bulletins et conseils")}
            </span>
          </div>
          <div class="grid gap-3 sm:grid-cols-3">
            <.link
              :for={step <- @setup_steps}
              id={"setup-step-#{step.key}"}
              navigate={step.path}
              class="group flex flex-col gap-1.5 rounded-lg border border-base-300 bg-base-100 p-3.5 transition-colors hover:border-base-content/30 hover:no-underline"
            >
              <span class="ta-num text-[1.4rem] font-semibold leading-tight text-warning">
                {step.value}
              </span>
              <span class="text-[0.9rem] font-semibold leading-snug">{step.title}</span>
              <span class="text-xs text-base-content/70">{step.sub}</span>
              <span class="mt-auto pt-1 text-[0.8rem] font-semibold text-primary">
                {step.action}
                <span
                  aria-hidden="true"
                  class="inline-block transition-transform group-hover:translate-x-0.5"
                >
                  →
                </span>
              </span>
            </.link>
          </div>
        </section>

        <div class="grid grid-cols-2 gap-2 sm:gap-3 lg:grid-cols-4">
          <.stat_tile
            :if={Scope.module?(@current_scope, :notes)}
            id="kpi-entry"
            navigate={~p"/school/sequences"}
            label={entry_label(@sequence)}
            value={pct_text(@grid && @grid.overall_pct)}
            tone={entry_tone(@grid && @grid.overall_pct)}
            sub={entry_sub(@sequence, @today, late_count(@grid))}
          />
          <.stat_tile
            :if={Scope.module?(@current_scope, :appel)}
            id="kpi-calls"
            navigate={~p"/school/day"}
            label={gettext("Appels aujourd'hui")}
            value={calls_value(@calls)}
            tone={if @calls.missed == [], do: :ok, else: :warn}
            sub={calls_sub(@calls)}
          />
          <.stat_tile
            :if={Scope.module?(@current_scope, :appel)}
            id="kpi-absences"
            navigate={~p"/school/absences"}
            label={gettext("Absences à justifier")}
            value={Integer.to_string(@absences.count)}
            tone={if @absences.count == 0, do: :ok, else: :warn}
            sub={
              ngettext(
                "%{count} élève au-delà de %{hours} h",
                "%{count} élèves au-delà de %{hours} h",
                @absences.flagged_students,
                hours: @absences.alert_hours
              )
            }
          />
          <.stat_tile
            :if={Scope.module?(@current_scope, :notes)}
            id="kpi-corrections"
            navigate={~p"/school/corrections/review"}
            label={gettext("Corrections")}
            value={Integer.to_string(@todo.pending_corrections)}
            tone={if @todo.pending_corrections == 0, do: :ok, else: :warn}
            sub={gettext("en attente de décision")}
          />
        </div>

        <div class="grid gap-4 lg:grid-cols-5">
          <div id="todo" class="ta-panel flex min-w-0 flex-col gap-1 lg:col-span-3">
            <h2 class="ta-eyebrow pb-1">{gettext("À traiter · %{n}", n: @todo_count)}</h2>
            <p :if={@todo_count == 0} id="todo-empty" class="py-2 text-sm text-base-content/70">
              {gettext("Rien à traiter")}
            </p>
            <ul class="flex flex-col">
              <.attention_row
                :if={@todo.pending_corrections > 0}
                id="todo-corrections"
                tone={:warning}
                title={
                  ngettext(
                    "%{count} correction de notes à décider",
                    "%{count} corrections de notes à décider",
                    @todo.pending_corrections
                  )
                }
                reason={
                  gettext("La plus ancienne date du %{date}",
                    date: Dates.day_month(@todo.oldest_correction)
                  )
                }
                action={gettext("Décider")}
                navigate={~p"/school/corrections/review"}
              />
              <.attention_row
                :if={late_count(@grid) > 0}
                id="todo-late"
                tone={:error}
                title={
                  ngettext(
                    "%{count} enseignant en retard de saisie",
                    "%{count} enseignants en retard de saisie",
                    late_count(@grid)
                  )
                }
                reason={late_sub(@sequence)}
                action={gettext("Relancer")}
                navigate={~p"/school/sequences"}
              />
              <.attention_row
                :if={@todo.councils_to_plan > 0}
                id="todo-councils"
                tone={:info}
                title={
                  ngettext(
                    "%{count} conseil de classe à planifier",
                    "%{count} conseils de classe à planifier",
                    @todo.councils_to_plan
                  )
                }
                reason={gettext("Trimestre %{n}", n: @todo.councils_term.position)}
                action={gettext("Planifier")}
                navigate={~p"/school/councils"}
              />
              <.attention_row
                :if={Scope.module?(@current_scope, :appel) and @calls.on_paper > 0}
                id="todo-paper"
                tone={:info}
                title={
                  ngettext(
                    "%{count} appel sur feuille à reporter",
                    "%{count} appels sur feuille à reporter",
                    @calls.on_paper
                  )
                }
                reason={gettext("Le surveillant général les saisit depuis « Aujourd'hui »")}
                action={gettext("Voir")}
                navigate={~p"/school/day"}
              />
              <.attention_row
                :if={@competence_gaps > 0}
                id="todo-competences"
                tone={:warning}
                title={
                  ngettext(
                    "%{count} cours sans compétence (APC)",
                    "%{count} cours sans compétence (APC)",
                    @competence_gaps
                  )
                }
                reason={
                  gettext("Séquence %{n} · à renseigner par les enseignants", n: @sequence.number)
                }
                action={gettext("Voir")}
                navigate={~p"/school/sequences"}
              />
            </ul>
          </div>

          <div
            :if={@sequence && @bars != []}
            id="entry-bars"
            class="ta-panel flex min-w-0 flex-col gap-2 lg:col-span-2"
          >
            <div class="flex items-center justify-between gap-3 pb-1">
              <h2 class="ta-eyebrow">
                {gettext("Saisie Séq. %{n} par niveau", n: @sequence.number)}
              </h2>
              <.link
                navigate={~p"/school/sequences"}
                class="shrink-0 text-xs font-semibold text-primary hover:underline"
              >
                {gettext("Détail →")}
              </.link>
            </div>
            <div
              :for={bar <- @bars}
              data-level={bar.label}
              class="grid grid-cols-[6rem_minmax(0,1fr)_3rem] items-center gap-3 text-sm"
              title={ngettext("%{count} classe", "%{count} classes", bar.classes)}
            >
              <span class="truncate font-semibold">{bar.label}</span>
              <div class="h-2 overflow-hidden rounded-full bg-base-300/60">
                <div
                  class={["h-full rounded-full transition-[width] duration-500", bar_tone(bar.pct)]}
                  style={"width: #{bar.pct || 0}%"}
                >
                </div>
              </div>
              <span class="ta-num text-right text-xs text-base-content/70">
                {pct_text(bar.pct)}
              </span>
            </div>
            <p class="pt-1 text-xs text-base-content/70">
              {gettext("Moyenne des cours de chaque niveau ; le détail par classe est dans le suivi.")}
            </p>
          </div>
        </div>

        <div :if={@my_units != []} id="dashboard-my-courses" class="ta-leaf space-y-2">
          <h2 class="ta-eyebrow">{gettext("Mes cours")}</h2>
          <p class="text-sm text-base-content/70">
            {ngettext("%{count} cours attribué", "%{count} cours attribués", length(@my_units),
              count: length(@my_units)
            )}
          </p>
          <.link navigate={~p"/school/courses"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-academic-cap" class="size-4" /> {gettext("Ouvrir mes cours")}
          </.link>
        </div>

        <%!-- "Mes classes" — the classes this head teacher also form-masters --%>
        <div :if={@my_classes != []} id="my-classes" class="ta-leaf space-y-2">
          <div class="flex items-center justify-between gap-3">
            <h2 class="ta-eyebrow">{gettext("Mes classes")}</h2>
            <span class="ta-num text-xs text-base-content/70">
              {ngettext("%{count} classe", "%{count} classes", length(@my_classes),
                count: length(@my_classes)
              )}
            </span>
          </div>
          <ul class="divide-y divide-base-300/70 text-sm">
            <li :for={c <- @my_classes} class="py-1.5 first:pt-0 last:pb-0">
              <.link
                navigate={~p"/school/classes/#{c.id}"}
                class="flex items-center justify-between gap-3 font-semibold hover:text-primary hover:no-underline"
              >
                <span class="truncate">{c.label}</span>
                <span class="ta-num shrink-0 text-xs font-normal text-base-content/70">
                  {c.level}
                </span>
              </.link>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :done?, :boolean, required: true
  slot :inner_block, required: true

  defp check_item(assigns) do
    ~H"""
    <li id={@id} class="flex items-center gap-2 py-1.5 first:pt-0 last:pb-0">
      <.icon
        name={if @done?, do: "hero-check-circle", else: "hero-x-circle"}
        class={"size-4 shrink-0 " <> if(@done?, do: "text-primary", else: "text-base-content/70")}
      />
      {render_slot(@inner_block)}
    </li>
    """
  end

  defp entry_tone(nil), do: :none
  defp entry_tone(100), do: :ok
  defp entry_tone(pct) when pct < 60, do: :error
  defp entry_tone(_pct), do: :warn

  defp bar_tone(nil), do: "bg-base-300"
  defp bar_tone(pct) when pct >= 90, do: "bg-primary"
  defp bar_tone(pct) when pct >= 60, do: "bg-warning"
  defp bar_tone(_pct), do: "bg-error"

  defp pct_text(nil), do: "—"
  defp pct_text(pct), do: "#{pct} %"

  defp late_count(nil), do: 0
  defp late_count(grid), do: grid.late_teacher_count

  defp entry_label(nil), do: gettext("Saisie des notes")
  defp entry_label(seq), do: gettext("Saisie Séq. %{n}", n: seq.number)

  # "mardi 3 novembre · Séquence 2 · clôture des notes le 9 déc."; the séquence part
  # only when known, the deadline part only when the séquence has one.
  defp eyebrow(today, seq) do
    [Dates.long(today) | sequence_parts(seq, today)] |> Enum.join(" · ")
  end

  defp sequence_parts(nil, _today), do: []

  defp sequence_parts(seq, today),
    do: [gettext("Séquence %{n}", n: seq.number) | List.wrap(deadline_text(seq, today))]

  defp deadline_text(%{grade_entry_deadline: %Date{} = deadline}, today) do
    if Date.compare(deadline, today) == :lt,
      do: gettext("notes clôturées le %{date}", date: Dates.day_month(deadline)),
      else: gettext("clôture des notes le %{date}", date: Dates.day_month(deadline))
  end

  defp deadline_text(_seq, _today), do: nil

  # « J-36 · 3 enseignants à relancer »: the countdown only up to the deadline.
  defp entry_sub(seq, today, late) do
    late_text =
      ngettext("%{count} enseignant à relancer", "%{count} enseignants à relancer", late)

    case seq && Dates.countdown(seq.grade_entry_deadline, today) do
      nil -> late_text
      countdown -> countdown <> " · " <> late_text
    end
  end

  defp late_sub(%{grade_entry_deadline: %Date{} = deadline} = seq),
    do:
      gettext("Séquence %{n} · clôture le %{date}",
        n: seq.number,
        date: Dates.day_month(deadline)
      )

  defp late_sub(seq), do: gettext("Séquence %{n}", n: seq.number)

  # The « Mise en place » cards: one per setup gap still open, each with its one action.
  defp setup_steps(todo) do
    pp = length(todo.classes_without_pp)
    unassigned = length(todo.unassigned)
    accounts = todo.pending_accounts

    [
      pp > 0 &&
        %{
          key: "pp",
          value: "#{pp} / #{todo.class_count}",
          title:
            ngettext(
              "Classe sans professeur principal",
              "Classes sans professeur principal",
              pp
            ),
          sub: gettext("Bloque leurs bulletins"),
          action: gettext("Désigner les PP"),
          path: ~p"/school/classes"
        },
      unassigned > 0 &&
        Map.merge(
          %{
            key: "unassigned",
            value: Integer.to_string(unassigned),
            title: ngettext("Matière sans enseignant", "Matières sans enseignant", unassigned)
          },
          unassigned_action(todo.unassigned)
        ),
      accounts.count > 0 &&
        %{
          key: "accounts",
          value: "#{accounts.count} / #{accounts.total}",
          title:
            ngettext(
              "Compte jamais connecté",
              "Comptes jamais connectés",
              accounts.count
            ),
          sub: accounts_sub(accounts),
          action: gettext("Voir les membres"),
          path: ~p"/school/members"
        }
    ]
    |> Enum.filter(& &1)
  end

  # A gap is one subject the coefficient grid expects in one class. A new subject is
  # « taught everywhere » until its cells are emptied, so far more gaps than a class
  # has subjects means the grid, not the assignments, needs the work: say so.
  @plausible_subjects_per_class 20

  defp unassigned_action(cells) do
    classes = cells |> Enum.map(& &1.class) |> Enum.uniq() |> length()
    per_class = div(length(cells), max(classes, 1))

    if per_class > @plausible_subjects_per_class do
      %{
        sub:
          gettext(
            "%{n} par classe en moyenne : la grille des coefficients donne des matières enseignées partout",
            n: per_class
          ),
        action: gettext("Vérifier la grille"),
        path: ~p"/school/settings/coefficients"
      }
    else
      %{
        sub: unassigned_sub(cells, classes),
        action: gettext("Affecter"),
        path: ~p"/school/settings/assignments"
      }
    end
  end

  # "dans 12 classes · Maths (6e A), Anglais (5e B)…"
  defp unassigned_sub(cells, classes) do
    examples =
      cells
      |> Enum.take(2)
      |> Enum.map_join(
        ", ",
        &gettext("%{subject} (%{class})", subject: &1.subject, class: &1.class)
      )

    more = if length(cells) > 2, do: "…", else: ""

    ngettext("dans %{count} classe", "dans %{count} classes", classes) <>
      " · " <> examples <> more
  end

  defp accounts_sub(%{expired: 0}), do: gettext("Mots de passe temporaires à remettre")

  defp accounts_sub(%{expired: expired}),
    do:
      gettext("Mots de passe temporaires à remettre") <>
        " · " <>
        ngettext("%{count} expiré", "%{count} expirés", expired)

  defp load_dashboard(socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year
    today = Reference.today()

    sequence =
      year && Assessment.default_sequence(Organization.list_sequences(scope, year), today)

    grid = sequence && Assessment.sequence_entry_grid(scope, year, sequence)

    calls =
      if year,
        do: Attendance.roll_call_counts(scope, today, Reference.now()),
        else: %{done: 0, on_paper: 0, expected: 0, missed: []}

    todo = Pilotage.todo(scope)
    competences = grid && Pilotage.competences(scope, sequence, grid)
    competence_gaps = if grid, do: Pilotage.competence_gaps(grid, competences), else: 0
    setup_complete? = Scope.setup_complete?(scope)
    show_setup? = not setup_complete? or not Scope.school_verified?(scope)

    socket
    |> assign(:year, year)
    |> assign(:today, today)
    |> assign(:sequence, sequence)
    |> assign(:grid, grid)
    |> assign(:bars, bars(grid))
    |> assign(:calls, calls)
    |> assign(:absences, Attendance.absences_to_justify(scope, today))
    |> assign(:todo, todo)
    |> assign(:setup_steps, setup_steps(todo))
    |> assign(:competence_gaps, competence_gaps)
    |> assign(:todo_count, todo_count(todo, grid, calls, competence_gaps, scope))
    |> assign(:setup_complete?, setup_complete?)
    |> assign(:show_setup?, show_setup?)
    |> assign_setup(show_setup?, scope)
    |> assign(
      :my_classes,
      if(year, do: Enrollment.list_form_master_classes(scope, year), else: [])
    )
    |> assign(:my_units, Curriculum.list_units_for_scope(scope))
  end

  # The checklist's own reads, only when it is shown.
  defp assign_setup(socket, false, _scope),
    do: assign(socket, profile_complete?: true, staff_count: 0)

  defp assign_setup(socket, true, scope) do
    profile_complete? =
      case Accounts.fetch_school_profile(scope) do
        {:ok, profile} -> profile.head_name not in [nil, ""]
        _ -> false
      end

    assign(socket,
      profile_complete?: profile_complete?,
      staff_count: scope |> Accounts.list_members() |> length()
    )
  end

  # The visible to-do rows (the setup gaps have their own block).
  defp todo_count(todo, grid, calls, competence_gaps, scope) do
    Enum.count(
      [
        todo.pending_corrections > 0,
        late_count(grid) > 0,
        todo.councils_to_plan > 0,
        Scope.module?(scope, :appel) and calls.on_paper > 0,
        competence_gaps > 0
      ],
      & &1
    )
  end

  # One bar per level: the mean of its classes' course cells' entry % (rounded down,
  # nil when no course is measurable), as the séquence grid computes the overall rate.
  defp bars(nil), do: []

  defp bars(grid) do
    grid.rows
    |> Enum.sort_by(&SchoolTemplates.class_sort_key(&1.class_group))
    |> Enum.chunk_by(& &1.class_group.level)
    |> Enum.map(fn [first | _] = rows ->
      pcts =
        for row <- rows,
            cell <- Map.values(row.cells),
            cell != nil,
            cell.pct != nil,
            do: cell.pct

      %{
        label: first.class_group.level || gettext("Autres"),
        classes: length(rows),
        pct: if(pcts == [], do: nil, else: div(Enum.sum(pcts), length(pcts)))
      }
    end)
  end

  # Every roll call of the day on paper: their number, none typed in yet.
  defp calls_value(%{on_paper: paper, expected: paper}) when paper > 0,
    do: Integer.to_string(paper)

  defp calls_value(calls), do: "#{calls.done} / #{calls.expected}"

  # « 2 non faits », or with paper classes (spec 2026-10-28) « 12 appels dans l'app · 30
  # sur feuille », the missed ones last; « tous sur feuille · 0 saisi » when all are.
  defp calls_sub(%{on_paper: paper, expected: paper}) when paper > 0,
    do: gettext("tous sur feuille · 0 saisi")

  defp calls_sub(%{on_paper: paper, done: done, missed: missed}) when paper > 0 do
    base =
      ngettext(
        "%{count} appel dans l'app · %{paper} sur feuille",
        "%{count} appels dans l'app · %{paper} sur feuille",
        done,
        paper: paper
      )

    if missed == [],
      do: base,
      else: base <> " · " <> ngettext("%{count} non fait", "%{count} non faits", length(missed))
  end

  defp calls_sub(%{missed: missed}),
    do: ngettext("%{count} non fait", "%{count} non faits", length(missed))
end
