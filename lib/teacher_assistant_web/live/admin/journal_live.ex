defmodule TeacherAssistantWeb.Admin.JournalLive do
  @moduledoc "Operator console spec §4–5: the audit journal, newest first, by 50."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.AuditEvent
  alias TeacherAssistantWeb.Dates

  @per_page 50

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    action =
      case AuditEvent.Action.match(params["action"] || "") do
        {:ok, action} -> action
        :error -> nil
      end

    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 -> n
        _ -> 1
      end

    # One extra row tells whether a next page exists.
    events =
      Accounts.list_audit_events(socket.assigns.current_scope,
        action: action,
        limit: @per_page + 1,
        offset: (page - 1) * @per_page
      )

    {:noreply,
     assign(socket,
       action: action,
       page: page,
       events: Enum.take(events, @per_page),
       more?: length(events) > @per_page
     )}
  end

  def handle_event("filter", %{"action" => action}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/admin/journal?#{%{action: action}}")}

  defp page_path(action, page), do: ~p"/admin/journal?#{%{action: action || "", page: page}}"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-journal" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Journal")} />

        <form id="journal-filter" phx-change="filter">
          <select name="action" class="select select-bordered select-sm">
            <option value="">{gettext("Toutes les actions")}</option>
            <option :for={a <- AuditEvent.Action.values()} value={a} selected={@action == a}>
              {AuditEvent.Action.label(a)}
            </option>
          </select>
        </form>

        <ul id="journal-events" class="divide-y divide-base-300 text-sm">
          <li :for={e <- @events} id={"event-#{e.id}"} class="py-2">
            <span class="font-medium">{AuditEvent.Action.label(e.action)}</span>
            <span :if={e.workspace}> · {e.workspace.name}</span>
            <span :if={e.target_user}> · {Accounts.User.display_name(e.target_user)}</span>
            <span :if={e.details["reason"]}> · {e.details["reason"]}</span>
            <span :if={e.details["after"]}> · {Enum.join(e.details["after"], ", ")}</span>
            <span class="block text-base-content/70">
              {e.actor && Accounts.User.display_name(e.actor)} · {Dates.short_datetime(e.inserted_at)}
            </span>
          </li>
        </ul>

        <div class="flex gap-2">
          <.link :if={@page > 1} patch={page_path(@action, @page - 1)} class="btn btn-sm">
            {gettext("Précédent")}
          </.link>
          <.link :if={@more?} patch={page_path(@action, @page + 1)} class="btn btn-sm">
            {gettext("Suivant")}
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
