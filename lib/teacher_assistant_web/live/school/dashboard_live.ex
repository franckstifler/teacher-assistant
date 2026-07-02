defmodule TeacherAssistantWeb.School.DashboardLive do
  use TeacherAssistantWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :scope, socket.assigns.current_scope)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-dashboard" class="space-y-4">
        <.page_header eyebrow={gettext("École")} title={@current_scope.current_workspace.name} />
      </section>
    </Layouts.app>
    """
  end
end
