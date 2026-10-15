defmodule TeacherAssistantWeb.School.NotificationsLive do
  @moduledoc """
  Spec KLM8: every notice of the signed-in member in this school, newest first,
  unread in bold. Opening one marks it read and follows its link. The bell in the
  shell (`NotificationHooks`) shows the 8 newest and links here.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Notifications
  alias TeacherAssistantWeb.NotificationText

  def mount(_params, _session, socket) do
    if socket.assigns.current_scope.current_workspace,
      do: {:ok, assign(socket, page: nil, page_number: 1)},
      else: {:ok, push_navigate(socket, to: ~p"/school")}
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, load(socket, parse_page(params["page"]))}

  def handle_event("open", %{"id" => id}, socket) do
    case Notifications.open(socket.assigns.current_scope, id) do
      {:ok, link} -> {:noreply, push_navigate(socket, to: link)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("read-all", _params, socket) do
    :ok = Notifications.mark_all_read(socket.assigns.current_scope)
    {:noreply, load(socket, socket.assigns.page_number)}
  end

  @doc "Called by `NotificationHooks` when the member's notices change (new, read)."
  def notifications_changed(socket), do: load(socket, socket.assigns.page_number)

  defp load(socket, n),
    do:
      assign(socket,
        page: Notifications.inbox(socket.assigns.current_scope, n),
        page_number: n
      )

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp pages(count), do: div(count + Notifications.page_size() - 1, Notifications.page_size())

  defp unread?(page), do: Enum.any?(page.results, &is_nil(&1.read_at))

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="notifications" class="mx-auto flex w-full max-w-2xl flex-col gap-4">
        <.page_header eyebrow={gettext("Messagerie")} title={gettext("Notifications")}>
          <:actions :if={unread?(@page)}>
            <button id="read-all" type="button" phx-click="read-all" class="btn btn-ghost btn-sm">
              <.icon name="hero-check" class="size-4" />
              {gettext("Tout marquer comme lu")}
            </button>
          </:actions>
        </.page_header>

        <div class="ta-panel flex flex-col gap-0.5 !p-1.5">
          <p
            :if={@page.results == []}
            id="notifications-empty"
            class="flex items-center gap-2 p-5 text-sm text-base-content/70"
          >
            <.icon name="hero-bell-slash" class="size-5 text-base-content/70" />
            {gettext("Aucune notification pour l'instant.")}
          </p>
          <button
            :for={n <- @page.results}
            id={"notification-#{n.id}"}
            type="button"
            phx-click="open"
            phx-value-id={n.id}
            data-unread={is_nil(n.read_at) && "true"}
            class={[
              "flex w-full items-start gap-3 rounded-box px-3 py-2.5 text-left transition-colors hover:bg-base-200",
              is_nil(n.read_at) && "bg-warning/5"
            ]}
          >
            <span class={[
              "mt-2 size-2 shrink-0 rounded-full",
              if(is_nil(n.read_at), do: "bg-warning", else: "bg-transparent")
            ]}></span>
            <span class="min-w-0 flex-1">
              <span class={["block text-[0.92rem]", is_nil(n.read_at) && "font-bold"]}>
                {NotificationText.title(n)}
              </span>
              <span data-role="detail" class="block text-xs text-base-content/70">
                {NotificationText.detail(n)}
              </span>
            </span>
            <span class="ta-num whitespace-nowrap text-right text-xs text-base-content/70">
              {NotificationText.when_text(n)}
            </span>
            <.icon name="hero-chevron-right" class="mt-1 size-4 shrink-0 text-base-content/30" />
          </button>
        </div>

        <nav
          :if={(@page.count || 0) > Notifications.page_size()}
          id="notifications-pager"
          aria-label={gettext("Pages")}
          class="flex flex-wrap gap-1"
        >
          <.link
            :for={p <- 1..pages(@page.count)}
            patch={~p"/school/notifications?page=#{p}"}
            aria-current={p == @page_number && "page"}
            class={[
              "rounded-full border px-3 py-1 text-sm font-medium transition-colors hover:border-primary",
              if(p == @page_number,
                do: "border-primary bg-primary/15 text-primary",
                else: "border-base-300 text-base-content/70"
              )
            ]}
          >
            {p}
          </.link>
        </nav>
      </section>
    </Layouts.app>
    """
  end
end
