defmodule TeacherAssistantWeb.Admin.JournalLive do
  @moduledoc "Placeholder until the operator console's Task 8."
  use TeacherAssistantWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
    </Layouts.app>
    """
  end
end
