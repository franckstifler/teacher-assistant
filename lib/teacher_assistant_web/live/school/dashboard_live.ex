defmodule TeacherAssistantWeb.School.DashboardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.Schools

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type == :school do
      {:ok, assign(socket, :scope, scope)}
    else
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-dashboard" class="space-y-4">
        <.page_header eyebrow={gettext("École")} title={@current_scope.current_workspace.name} />

        <.stat
          label={gettext("Members")}
          value={Integer.to_string(length(Schools.list_members(@current_scope.current_workspace)))}
        />

        <.empty_state
          icon="hero-user-group"
          title={gettext("Classes & enrollment coming next")}
        />
      </section>
    </Layouts.app>
    """
  end
end
