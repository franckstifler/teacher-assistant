defmodule TeacherAssistantWeb.Admin.OverviewLive do
  @moduledoc "Operator console spec §5: the platform at a glance."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Operator}
  alias TeacherAssistant.Accounts.AuditEvent
  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       overview: Operator.overview(scope),
       events: Accounts.list_audit_events(scope, limit: 10)
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-overview" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Vue d'ensemble")} />

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
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
            class="ta-leaf p-4"
          >
            <span class="ta-num block text-2xl font-semibold">{@overview.schools[status]}</span>
            <span class="text-sm text-base-content/70">{label}</span>
          </.link>
          <.link
            id="overview-schools-suspended"
            navigate={~p"/admin/schools?#{%{suspended: 1}}"}
            class="ta-leaf p-4"
          >
            <span class="ta-num block text-2xl font-semibold">{@overview.schools.suspended}</span>
            <span class="text-sm text-base-content/70">{gettext("Suspendus")}</span>
          </.link>
        </div>

        <dl class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div
            :for={
              {key, label} <- [
                members: gettext("Membres actifs"),
                students: gettext("Élèves inscrits"),
                roll_calls_7d: gettext("Appels (7 jours)"),
                marks_7d: gettext("Notes saisies (7 jours)")
              ]
            }
            id={"overview-#{key}"}
            class="ta-leaf p-4"
          >
            <dt class="text-sm text-base-content/70">{label}</dt>
            <dd class="ta-num text-xl font-semibold">{@overview[key]}</dd>
          </div>
        </dl>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Dernières actions")}</h2>
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
      </section>
    </Layouts.app>
    """
  end
end
