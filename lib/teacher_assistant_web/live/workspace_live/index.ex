defmodule TeacherAssistantWeb.WorkspaceLive.Index do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.Workspaces

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="workspace-selection" class="space-y-6">
        <div class="flex flex-col gap-2">
          <p class="ta-section-label">{gettext("Workspace")}</p>
          <h1 class="text-2xl font-semibold tracking-normal">
            {gettext("Choose where you want to work")}
          </h1>
          <p class="max-w-2xl text-sm text-base-content/65">
            {gettext(
              "Your personal teacher workspace is always available. School workspaces appear when an administrator invites you."
            )}
          </p>
        </div>

        <div id="workspace-list" class="grid gap-3 lg:grid-cols-2">
          <div
            :for={workspace <- @workspaces}
            id={"workspace-#{workspace.id}"}
            class="ta-panel flex items-center justify-between gap-4 p-5"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <.icon
                  name={workspace_icon(workspace)}
                  class="size-5 text-primary"
                />
                <h2 class="truncate text-base font-semibold">{workspace.name}</h2>
              </div>
              <p class="mt-1 text-sm text-base-content/60">
                {workspace_label(workspace)}
              </p>
            </div>

            <.link
              id={"select-workspace-#{workspace.id}"}
              href={~p"/workspaces/select/#{workspace.id}"}
              class="btn btn-primary btn-sm shrink-0"
            >
              {gettext("Open")}
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Workspaces"))
     |> assign(:workspaces, Workspaces.list_workspaces(socket.assigns.current_user))}
  end

  defp workspace_icon(%{workspace_type: :personal_teacher}), do: "hero-user-circle"
  defp workspace_icon(_workspace), do: "hero-building-library"

  defp workspace_label(%{workspace_type: :personal_teacher}),
    do: gettext("Private pedagogic tools, attendance, and marks")

  defp workspace_label(_workspace), do: gettext("School administration and official workflows")
end
