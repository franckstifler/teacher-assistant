defmodule TeacherAssistantWeb.School.SuspendedLive do
  @moduledoc "Operator console spec §2: where a suspended school's members wait."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Scope

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.suspended?(scope),
      do: {:ok, assign(socket, :reason, scope.current_workspace.suspension_reason)},
      else: {:ok, push_navigate(socket, to: ~p"/school")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-suspended" class="mx-auto max-w-xl space-y-4">
        <.page_header
          eyebrow={@current_scope.current_workspace.name}
          title={gettext("Établissement suspendu")}
        />
        <p class="ta-leaf p-4">
          <span class="block text-sm text-base-content/70">{gettext("Motif")}</span>
          <span id="suspension-reason">{@reason}</span>
        </p>
        <p class="text-sm text-base-content/70">
          {gettext(
            "Contactez l'administrateur de Teacher Assistant pour rétablir l'accès. Si vous appartenez à un autre établissement, choisissez-le dans le menu."
          )}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
