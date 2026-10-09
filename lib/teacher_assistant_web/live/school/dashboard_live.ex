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

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.{Reference, SchoolTemplates}
  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope.current_workspace != nil and landing_elsewhere(scope) != nil ->
        {:ok, push_navigate(socket, to: landing_elsewhere(scope))}

      scope.current_workspace != nil ->
        {:ok,
         socket
         |> assign(:scope, scope)
         |> load_dashboard()}

      true ->
        # A stale workspace id (or a deactivated membership) can leave the
        # resolved scope without a workspace even though the user has a real
        # school — send them there instead of prompting to create a new one.
        case Organization.list_workspaces_for(%TeacherAssistant.Scope{
               current_user: scope.current_user
             }) do
          [first | _] -> {:ok, push_navigate(socket, to: ~p"/workspaces/select/#{first.id}")}
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="dashboard" class="flex flex-col gap-5">
        <.page_header
          eyebrow={eyebrow(@today, @sequence)}
          title={gettext("Bonjour, %{name}", name: User.display_name(@current_scope.current_user))}
        />

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

        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <.kpi_link
            id="kpi-entry"
            navigate={~p"/school/sequences"}
            label={entry_label(@sequence)}
            value={pct_text(@grid && @grid.overall_pct)}
            tone={entry_tone(@grid && @grid.overall_pct)}
            sub={
              ngettext(
                "%{count} enseignant à relancer",
                "%{count} enseignants à relancer",
                late_count(@grid)
              )
            }
          />
          <.kpi_link
            id="kpi-calls"
            navigate={~p"/school/day"}
            label={gettext("Appels aujourd'hui")}
            value={"#{@calls.done} / #{@calls.expected}"}
            tone={if @calls.missed == [], do: :ok, else: :warn}
            sub={ngettext("%{count} non fait", "%{count} non faits", length(@calls.missed))}
          />
          <.kpi_link
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
          <.kpi_link
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
            <p :if={@todo_count == 0} id="todo-empty" class="py-2 text-sm text-base-content/60">
              {gettext("Rien à traiter")}
            </p>
            <ul class="flex flex-col">
              <.todo_row
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
                sub={
                  gettext("La plus ancienne date du %{date}",
                    date: Dates.day_month(@todo.oldest_correction)
                  )
                }
                cta={gettext("Décider")}
                navigate={~p"/school/corrections/review"}
              />
              <.todo_row
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
                sub={late_sub(@sequence)}
                cta={gettext("Relancer")}
                navigate={~p"/school/sequences"}
              />
              <li :if={@todo.classes_without_pp != []} id="todo-no-pp">
                <ul class="flex flex-col">
                  <.todo_row
                    :for={cg <- Enum.take(@todo.classes_without_pp, 3)}
                    id={"todo-no-pp-#{cg.id}"}
                    tone={:error}
                    title={gettext("%{class} sans professeur principal", class: cg.label)}
                    sub={
                      ngettext(
                        "%{count} élève · bulletins bloqués sans PP",
                        "%{count} élèves · bulletins bloqués sans PP",
                        cg.enrollment_count
                      )
                    }
                    cta={gettext("Désigner")}
                    navigate={~p"/school/classes/#{cg.id}"}
                  />
                </ul>
                <.link
                  :if={length(@todo.classes_without_pp) > 3}
                  id="todo-no-pp-more"
                  navigate={~p"/school/classes"}
                  class="ta-row-rule block py-2 pl-4 text-xs font-semibold text-base-content/70 hover:text-primary"
                >
                  {gettext("+ %{n} autres", n: length(@todo.classes_without_pp) - 3)}
                </.link>
              </li>
              <.todo_row
                :if={@todo.unassigned != []}
                id="todo-unassigned"
                tone={:warning}
                title={
                  ngettext(
                    "%{count} matière sans enseignant",
                    "%{count} matières sans enseignant",
                    length(@todo.unassigned)
                  )
                }
                sub={unassigned_sub(@todo.unassigned)}
                cta={gettext("Affecter")}
                navigate={~p"/school/settings/assignments"}
              />
              <.todo_row
                :if={@todo.pending_accounts.count > 0}
                id="todo-accounts"
                tone={:info}
                title={
                  ngettext(
                    "%{count} compte en attente de première connexion",
                    "%{count} comptes en attente de première connexion",
                    @todo.pending_accounts.count
                  )
                }
                sub={
                  @todo.pending_accounts.expired > 0 &&
                    ngettext(
                      "Dont %{count} mot de passe temporaire expiré",
                      "Dont %{count} mots de passe temporaires expirés",
                      @todo.pending_accounts.expired
                    )
                }
                cta={gettext("Voir")}
                navigate={~p"/school/members"}
              />
              <.todo_row
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
                sub={gettext("Trimestre %{n}", n: @todo.councils_term.position)}
                cta={gettext("Planifier")}
                navigate={~p"/school/councils"}
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
                {gettext("Saisie Séquence %{n} par classe", n: @sequence.number)}
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
              data-class={bar.label}
              class="grid grid-cols-[4.5rem_minmax(0,1fr)_3rem] items-center gap-3 text-sm"
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
            <span class="ta-num text-xs text-base-content/60">
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
                <span class="ta-num shrink-0 text-xs font-normal text-base-content/60">
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
        class={"size-4 shrink-0 " <> if(@done?, do: "text-primary", else: "text-base-content/40")}
      />
      {render_slot(@inner_block)}
    </li>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :atom, required: true
  attr :sub, :string, required: true

  defp kpi_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="ta-leaf group flex flex-col gap-1 transition hover:-translate-y-0.5 hover:border-primary/60 hover:no-underline"
    >
      <span class="ta-eyebrow flex items-center justify-between gap-2">
        {@label}
        <.icon
          name="hero-arrow-up-right"
          class="size-3.5 opacity-0 transition group-hover:opacity-70"
        />
      </span>
      <span class={["ta-num text-3xl font-semibold leading-tight", kpi_tone(@tone)]}>
        {@value}
      </span>
      <span class="text-xs text-base-content/70">{@sub}</span>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :tone, :atom, required: true
  attr :title, :string, required: true
  attr :sub, :any, default: nil
  attr :cta, :string, required: true
  attr :navigate, :string, required: true

  defp todo_row(assigns) do
    ~H"""
    <li id={@id} class="ta-row-rule flex items-center gap-3 py-2.5 last:border-b-0">
      <span class={["w-1 self-stretch shrink-0 rounded-full", mark_tone(@tone)]} aria-hidden="true"></span>
      <div class="flex min-w-0 flex-1 flex-col">
        <span class="text-[0.9rem] font-semibold leading-snug">{@title}</span>
        <span :if={@sub} class="text-[0.76rem] text-base-content/70">{@sub}</span>
      </div>
      <.link navigate={@navigate} class="btn btn-outline btn-xs shrink-0">{@cta}</.link>
    </li>
    """
  end

  defp kpi_tone(:ok), do: "text-primary"
  defp kpi_tone(:warn), do: "text-warning"
  defp kpi_tone(:error), do: "text-error"
  defp kpi_tone(:none), do: "text-base-content/50"

  defp mark_tone(:warning), do: "bg-warning"
  defp mark_tone(:error), do: "bg-error"
  defp mark_tone(:info), do: "bg-info"

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

  # "jeudi 9 octobre · Séquence 2 · J-3"; the séquence and J-n parts only when known
  # (J-n only up to the entry deadline).
  defp eyebrow(today, seq) do
    [Dates.long(today) | sequence_parts(seq, today)] |> Enum.join(" · ")
  end

  defp sequence_parts(nil, _today), do: []

  defp sequence_parts(seq, today) do
    days =
      case seq.grade_entry_deadline do
        %Date{} = deadline -> Date.diff(deadline, today)
        _ -> nil
      end

    [gettext("Séquence %{n}", n: seq.number)] ++
      if(is_integer(days) and days >= 0, do: [gettext("J-%{d}", d: days)], else: [])
  end

  defp late_sub(%{grade_entry_deadline: %Date{} = deadline} = seq),
    do:
      gettext("Séquence %{n} · clôture le %{date}",
        n: seq.number,
        date: Dates.day_month(deadline)
      )

  defp late_sub(seq), do: gettext("Séquence %{n}", n: seq.number)

  # "Maths (6e A), Anglais (5e B) + 3 autres"
  defp unassigned_sub(cells) do
    shown =
      cells
      |> Enum.take(3)
      |> Enum.map_join(
        ", ",
        &gettext("%{subject} (%{class})", subject: &1.subject, class: &1.class)
      )

    case length(cells) - 3 do
      more when more > 0 -> shown <> " " <> gettext("+ %{n} autres", n: more)
      _ -> shown
    end
  end

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
        else: %{done: 0, expected: 0, missed: []}

    todo = Pilotage.todo(scope)
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
    |> assign(:todo_count, todo_count(todo, grid))
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

  # The visible to-do rows (a class without PP is a row, at most three).
  defp todo_count(todo, grid) do
    [
      todo.pending_corrections > 0,
      late_count(grid) > 0,
      todo.unassigned != [],
      todo.pending_accounts.count > 0,
      todo.councils_to_plan > 0
    ]
    |> Enum.count(& &1)
    |> Kernel.+(min(length(todo.classes_without_pp), 3))
  end

  # One bar per class: the mean of its course cells' entry % (rounded down, nil when
  # no course is measurable), as the séquence grid computes the overall rate.
  defp bars(nil), do: []

  defp bars(grid) do
    grid.rows
    |> Enum.sort_by(&SchoolTemplates.class_sort_key(&1.class_group))
    |> Enum.map(fn row ->
      pcts =
        row.cells
        |> Map.values()
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.pct)
        |> Enum.reject(&is_nil/1)

      %{
        label: row.class_group.label,
        pct: if(pcts == [], do: nil, else: div(Enum.sum(pcts), length(pcts)))
      }
    end)
  end
end
