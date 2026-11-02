defmodule TeacherAssistantWeb.Admin.OverviewLive do
  @moduledoc """
  Operator console spec §5: the platform at a glance — what needs the operator, growth, the
  activation funnel, the last weeks' use, module adoption, the most active schools and system
  health.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Modules, Operator}
  alias TeacherAssistant.Accounts.AuditEvent
  alias TeacherAssistantWeb.Dates

  defp list_limit, do: 5

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       page_title: gettext("Vue d'ensemble"),
       overview: Operator.overview(scope),
       events: Accounts.list_audit_events(scope, limit: 10),
       now: DateTime.utc_now()
     )}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        attention_count:
          length(assigns.overview.attention.pending) + length(assigns.overview.attention.quiet) +
            length(assigns.overview.attention.silent) + assigns.overview.system.jobs.failed
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-overview" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Vue d'ensemble")}>
          <:actions>
            <.side_chip id="overview-updated">
              {gettext("Mis à jour %{at}", at: Dates.short_datetime(@now))}
            </.side_chip>
          </:actions>
        </.page_header>

        <div id="overview-attention" class="ta-panel flex flex-col gap-1">
          <h2 class="ta-eyebrow pb-1">{gettext("À traiter · %{n}", n: @attention_count)}</h2>
          <p
            :if={@attention_count == 0}
            id="attention-empty"
            class="py-2 text-sm text-base-content/70"
          >
            {gettext("Rien à traiter")}
          </p>
          <ul class="flex flex-col">
            <.todo_row
              :for={s <- Enum.take(@overview.attention.pending, list_limit())}
              id={"attention-pending-#{s.id}"}
              tone={:warning}
              title={gettext("%{name} attend sa vérification", name: s.name)}
              sub={waiting_text(s.since, @now)}
              cta={gettext("Vérifier")}
              navigate={~p"/admin/schools/#{s.id}"}
            />
            <.todo_row
              :for={s <- Enum.take(@overview.attention.quiet, list_limit())}
              id={"attention-quiet-#{s.id}"}
              tone={:error}
              title={gettext("%{name} ne saisit plus rien", name: s.name)}
              sub={gettext("Dernière saisie le %{date}", date: Dates.short(local_date(s.last_at)))}
              cta={gettext("Voir")}
              navigate={~p"/admin/schools/#{s.id}"}
            />
            <.todo_row
              :for={s <- Enum.take(@overview.attention.silent, list_limit())}
              id={"attention-silent-#{s.id}"}
              tone={:neutral}
              title={gettext("%{name} n'a encore rien saisi", name: s.name)}
              sub={gettext("Inscrit le %{date}", date: Dates.short(DateTime.to_date(s.since)))}
              cta={gettext("Voir")}
              navigate={~p"/admin/schools/#{s.id}"}
            />
            <li
              :if={@overview.system.jobs.failed > 0}
              id="attention-jobs"
              class="ta-row-rule flex min-h-14 items-center gap-3 py-2.5 last:border-b-0 sm:min-h-0"
            >
              <span class="size-2 shrink-0 rounded-full bg-error" aria-hidden="true"></span>
              <span class="text-[0.95rem] font-semibold leading-snug">
                {ngettext(
                  "%{count} tâche de fond abandonnée après échecs",
                  "%{count} tâches de fond abandonnées après échecs",
                  @overview.system.jobs.failed
                )}
              </span>
            </li>
          </ul>
          <.link
            :if={length(@overview.attention.pending) > list_limit()}
            navigate={~p"/admin/schools?#{%{status: :unverified}}"}
            class="link pt-1 text-sm"
          >
            {gettext("Toute la file de vérification")}
          </.link>
        </div>

        <div class="grid grid-cols-2 gap-2 sm:gap-3 lg:grid-cols-4">
          <.kpi
            id="overview-active-schools"
            label={gettext("Établissements actifs · 7 j")}
            value={"#{@overview.usage.active_schools} / #{@overview.usage.live_schools}"}
            sub={gettext("ont saisi au moins une donnée")}
          />
          <.kpi
            id="overview-active-users"
            label={gettext("Utilisateurs actifs · 7 j")}
            value={Integer.to_string(@overview.usage.active_users)}
            sub={
              ngettext(
                "sur %{count} membre actif",
                "sur %{count} membres actifs",
                @overview.members
              )
            }
          />
          <.kpi
            id="overview-new-schools"
            label={gettext("Nouveaux établissements · 30 j")}
            value={Integer.to_string(@overview.growth.new_schools)}
            sub={trend(@overview.growth.new_schools, @overview.growth.new_schools_before)}
          />
          <.kpi
            id="overview-new-users"
            label={gettext("Nouveaux utilisateurs · 30 j")}
            value={Integer.to_string(@overview.growth.new_users)}
            sub={trend(@overview.growth.new_users, @overview.growth.new_users_before)}
          />
        </div>

        <div class="grid gap-4 lg:grid-cols-5">
          <section id="overview-weekly" class="ta-panel flex min-w-0 flex-col gap-3 lg:col-span-3">
            <header>
              <h2 class="font-semibold">{gettext("Activité sur 12 semaines")}</h2>
              <p class="ta-text-2 text-sm">
                {gettext(
                  "Données saisies par semaine : notes, appels, absences, sanctions, paiements."
                )}
              </p>
            </header>
            <.weekly_bars weeks={@overview.weekly} />
          </section>

          <section id="overview-funnel" class="ta-panel flex min-w-0 flex-col gap-3 lg:col-span-2">
            <header>
              <h2 class="font-semibold">{gettext("Parcours d'activation")}</h2>
              <p class="ta-text-2 text-sm">
                {gettext("Chaque étape ne garde que les établissements de l'étape précédente.")}
              </p>
            </header>
            <ol class="flex flex-col gap-3">
              <.funnel_step
                :for={
                  {key, label} <- [
                    signed_up: gettext("Inscrits"),
                    verified: gettext("Vérifiés"),
                    set_up: gettext("Élèves inscrits"),
                    active: gettext("Actifs cette semaine")
                  ]
                }
                id={"funnel-#{key}"}
                label={label}
                value={@overview.funnel[key]}
                total={@overview.funnel.signed_up}
              />
            </ol>
          </section>
        </div>

        <div class="grid gap-4 lg:grid-cols-5">
          <section
            id="overview-top-schools"
            class="ta-panel flex min-w-0 flex-col gap-2 lg:col-span-3"
          >
            <h2 class="font-semibold">{gettext("Établissements les plus actifs · 7 j")}</h2>
            <p :if={@overview.top_schools == []} class="py-2 text-sm text-base-content/70">
              {gettext("Aucune saisie cette semaine.")}
            </p>
            <div :if={@overview.top_schools != []} class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Établissement")}</th>
                    <th class="text-right">{gettext("Élèves")}</th>
                    <th class="text-right">{gettext("Saisies")}</th>
                    <th class="text-right">{gettext("Dernière")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={s <- @overview.top_schools} id={"top-school-#{s.id}"}>
                    <td>
                      <.link navigate={~p"/admin/schools/#{s.id}"} class="link link-hover font-medium">
                        {s.name}
                      </.link>
                      <span :if={s.town} class="ta-text-2 block text-xs">{s.town}</span>
                    </td>
                    <td class="ta-num text-right">{s.students}</td>
                    <td class="ta-num text-right">{s.actions_7d}</td>
                    <td class="ta-text-2 text-right text-xs">
                      {Dates.relative(local_date(s.last_at), local_date(@now))}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section id="overview-modules" class="ta-panel flex min-w-0 flex-col gap-2 lg:col-span-2">
            <h2 class="font-semibold">{gettext("Modules")}</h2>
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Module")}</th>
                  <th class="text-right">{gettext("Activé")}</th>
                  <th class="text-right">{gettext("Utilisé · 30 j")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={key <- Modules.keys()} id={"module-#{key}"}>
                  <td>{Modules.label(key)}</td>
                  <td class="ta-num text-right">{@overview.modules[key].enabled}</td>
                  <td class="ta-num text-right">{@overview.modules[key].used || "—"}</td>
                </tr>
              </tbody>
            </table>
            <p class="ta-text-2 text-xs">
              {gettext("« — » : ce module ne laisse pas de trace de saisie à compter.")}
            </p>
          </section>
        </div>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Parc")}</h2>
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
            <.link
              :for={
                {status, label} <- [
                  unverified: gettext("À vérifier"),
                  verified: gettext("Vérifiés"),
                  rejected: gettext("Rejetés")
                ]
              }
              id={"overview-schools-#{status}"}
              navigate={~p"/admin/schools?#{%{status: status}}"}
              class="ta-leaf p-4 transition-colors hover:border-base-content/30 hover:no-underline"
            >
              <span class="ta-num block text-2xl font-semibold">{@overview.schools[status]}</span>
              <span class="text-sm text-base-content/70">{label}</span>
            </.link>
            <.link
              id="overview-schools-suspended"
              navigate={~p"/admin/schools?#{%{suspended: 1}}"}
              class="ta-leaf p-4 transition-colors hover:border-base-content/30 hover:no-underline"
            >
              <span class="ta-num block text-2xl font-semibold">{@overview.schools.suspended}</span>
              <span class="text-sm text-base-content/70">{gettext("Suspendus")}</span>
            </.link>
            <div id="overview-members" class="ta-leaf p-4">
              <span class="ta-num block text-2xl font-semibold">{@overview.members}</span>
              <span class="text-sm text-base-content/70">{gettext("Membres actifs")}</span>
            </div>
            <div id="overview-students" class="ta-leaf p-4">
              <span class="ta-num block text-2xl font-semibold">{@overview.students}</span>
              <span class="text-sm text-base-content/70">{gettext("Élèves inscrits")}</span>
            </div>
          </div>
        </section>

        <div class="grid gap-4 lg:grid-cols-5">
          <section class="ta-panel flex min-w-0 flex-col gap-2 lg:col-span-3">
            <h2 class="font-semibold">{gettext("Dernières actions")}</h2>
            <p :if={@events == []} class="py-2 text-sm text-base-content/70">
              {gettext("Aucune action enregistrée.")}
            </p>
            <ul id="overview-events" class="divide-y divide-base-300">
              <li :for={e <- @events} id={"event-#{e.id}"} class="py-2 text-sm">
                {AuditEvent.Action.label(e.action)}
                <span :if={e.workspace}> · {e.workspace.name}</span>
                <span :if={e.target_user}> · {Accounts.User.display_name(e.target_user)}</span>
                <span class="text-base-content/70"> · {Dates.short_datetime(e.inserted_at)}</span>
              </li>
            </ul>
            <.link navigate={~p"/admin/journal"} class="link text-sm">
              {gettext("Tout le journal")}
            </.link>
          </section>

          <section id="overview-system" class="ta-panel flex min-w-0 flex-col gap-2 lg:col-span-2">
            <h2 class="font-semibold">{gettext("Système")}</h2>
            <dl class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1.5 text-sm">
              <dt class="ta-text-2">{gettext("Version")}</dt>
              <dd class="ta-num text-right">{@overview.system.version}</dd>
              <dt class="ta-text-2">{gettext("En ligne depuis")}</dt>
              <dd class="ta-num text-right">{duration(@overview.system.uptime_ms)}</dd>
              <dt class="ta-text-2">{gettext("Base de données")}</dt>
              <dd class="ta-num text-right">{bytes(@overview.system.db_bytes)}</dd>
              <dt class="ta-text-2">{gettext("Mémoire")}</dt>
              <dd class="ta-num text-right">{bytes(@overview.system.memory_bytes)}</dd>
              <dt class="ta-text-2">{gettext("Tâches en attente")}</dt>
              <dd id="system-jobs-waiting" class="ta-num text-right">
                {@overview.system.jobs.waiting}
              </dd>
              <dt class="ta-text-2">{gettext("Tâches à réessayer")}</dt>
              <dd
                id="system-jobs-retrying"
                class={["ta-num text-right", @overview.system.jobs.retrying > 0 && "text-warning"]}
              >
                {@overview.system.jobs.retrying}
              </dd>
              <dt class="ta-text-2">{gettext("Tâches abandonnées")}</dt>
              <dd
                id="system-jobs-failed"
                class={["ta-num text-right", @overview.system.jobs.failed > 0 && "text-error"]}
              >
                {@overview.system.jobs.failed}
              </dd>
              <dt class="ta-text-2">{gettext("Dernière tâche réussie")}</dt>
              <dd class="ta-num text-right">
                {if @overview.system.last_job_at,
                  do: Dates.short_datetime(@overview.system.last_job_at),
                  else: "—"}
              </dd>
            </dl>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :tone, :atom, required: true
  attr :title, :string, required: true
  attr :sub, :string, default: nil
  attr :cta, :string, required: true
  attr :navigate, :string, required: true

  defp todo_row(assigns) do
    ~H"""
    <li id={@id} class="ta-row-rule last:border-b-0">
      <.link
        navigate={@navigate}
        class="group flex min-h-14 items-center gap-3 rounded-lg py-2.5 hover:no-underline sm:min-h-0"
      >
        <span class={["size-2 shrink-0 rounded-full", tone_class(@tone)]} aria-hidden="true"></span>
        <span class="flex min-w-0 flex-1 flex-col">
          <span class="text-[0.95rem] font-semibold leading-snug">{@title}</span>
          <span :if={@sub} class="text-[0.8rem] text-base-content/70">{@sub}</span>
        </span>
        <span class="flex items-center gap-1 text-sm font-medium text-primary">
          {@cta}
          <.icon
            name="hero-chevron-right"
            class="size-3.5 transition-transform group-hover:translate-x-0.5"
          />
        </span>
      </.link>
    </li>
    """
  end

  defp tone_class(:warning), do: "bg-warning"
  defp tone_class(:error), do: "bg-error"
  defp tone_class(:neutral), do: "bg-base-content/40"

  attr :weeks, :list, required: true

  # One bar per week, height relative to the busiest week; the hover title gives the figures.
  defp weekly_bars(assigns) do
    assigns =
      assign(assigns, max: assigns.weeks |> Enum.map(& &1.actions) |> Enum.max(fn -> 0 end))

    ~H"""
    <div>
      <div
        class="flex h-40 items-end gap-[2px] border-b border-base-300"
        role="img"
        aria-label={gettext("Saisies par semaine sur 12 semaines")}
      >
        <div
          :for={w <- @weeks}
          id={"week-#{w.week}"}
          class="group relative flex h-full flex-1 items-end"
          title={week_title(w)}
        >
          <div
            class={[
              "w-full rounded-t-[4px] transition-colors",
              if(w.actions > 0, do: "bg-primary/80 group-hover:bg-primary", else: "bg-base-300")
            ]}
            style={"height: #{bar_height(w.actions, @max)}%"}
          >
          </div>
        </div>
      </div>
      <div class="ta-text-2 mt-1 flex justify-between text-[0.7rem]">
        <span>{Dates.day_month(hd(@weeks).week)}</span>
        <span>{gettext("cette semaine")}</span>
      </div>
      <table class="sr-only">
        <caption>{gettext("Saisies par semaine")}</caption>
        <tr :for={w <- @weeks}>
          <th>{Dates.day_month(w.week)}</th>
          <td>{w.actions}</td>
          <td>{w.schools}</td>
        </tr>
      </table>
    </div>
    """
  end

  defp bar_height(_actions, 0), do: 2
  defp bar_height(0, _max), do: 2
  defp bar_height(actions, max), do: max(round(actions / max * 100), 3)

  defp week_title(w) do
    gettext("Semaine du %{date} : %{actions} saisies, %{schools} établissements",
      date: Dates.day_month(w.week),
      actions: w.actions,
      schools: w.schools
    )
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :total, :integer, required: true

  defp funnel_step(assigns) do
    assigns =
      assign(assigns,
        pct: if(assigns.total > 0, do: round(assigns.value / assigns.total * 100), else: 0)
      )

    ~H"""
    <li id={@id} class="flex flex-col gap-1">
      <span class="flex items-baseline justify-between gap-2 text-sm">
        <span>{@label}</span>
        <span class="ta-num">
          {@value} <span class="ta-text-2 text-xs">· {@pct} %</span>
        </span>
      </span>
      <span class="block h-2 overflow-hidden rounded-full bg-base-300">
        <span class="block h-full rounded-full bg-primary/80" style={"width: #{@pct}%"}></span>
      </span>
    </li>
    """
  end

  # The day in Cameroon (UTC+1), as `Dates.short_datetime/1` shows it.
  defp local_date(at), do: at |> DateTime.add(3600) |> DateTime.to_date()

  defp waiting_text(since, now) do
    days = DateTime.diff(now, since, :day)
    ngettext("En attente depuis %{count} jour", "En attente depuis %{count} jours", days)
  end

  defp trend(now, before) when now > before,
    do: gettext("+%{n} par rapport aux 30 jours précédents", n: now - before)

  defp trend(now, before) when now < before,
    do: gettext("−%{n} par rapport aux 30 jours précédents", n: before - now)

  defp trend(_now, _before), do: gettext("autant que les 30 jours précédents")

  defp bytes(n) when n >= 1_073_741_824,
    do: gettext("%{n} Go", n: Float.round(n / 1_073_741_824, 1))

  defp bytes(n) when n >= 1_048_576, do: gettext("%{n} Mo", n: Float.round(n / 1_048_576, 1))
  defp bytes(n), do: gettext("%{n} Ko", n: div(n, 1024))

  defp duration(ms) do
    minutes = div(ms, 60_000)

    case {div(minutes, 1440), div(rem(minutes, 1440), 60), rem(minutes, 60)} do
      {0, 0, m} -> gettext("%{m} min", m: m)
      {0, h, m} -> gettext("%{h} h %{m} min", h: h, m: m)
      {d, h, _m} -> gettext("%{d} j %{h} h", d: d, h: h)
    end
  end
end
