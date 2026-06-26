defmodule TeacherAssistantWeb.Teacher.DashboardLive do
  use TeacherAssistantWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-dashboard" class="p-4">
        <h1 class="text-xl font-semibold">{gettext("Teacher dashboard")}</h1>
      </section>
    </Layouts.app>
    """
  end
end
