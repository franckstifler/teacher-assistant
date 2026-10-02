defmodule TeacherAssistantWeb.School.StudentLive do
  use TeacherAssistantWeb, :live_view
  def mount(_params, _session, socket), do: {:ok, push_navigate(socket, to: ~p"/school/students")}
  def render(assigns), do: ~H""
end
