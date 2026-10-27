defmodule TeacherAssistantWeb.School.RolesLive do
  @moduledoc "Settings → Rôles et droits (spec KLM7, S06): rights × roles, read only."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.SchoolRole

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, assign(socket, rights: SchoolRole.rights(), roles: SchoolRole.values())}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="roles" class="space-y-4">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Rôles et droits")}
        />
        <p class="text-sm text-base-content/70">
          {gettext("Les droits suivent le rôle ; ils ne sont pas modifiables pour l'instant.")}
        </p>
        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table id="rights-matrix" class="table table-sm">
            <thead>
              <tr>
                <th class="sticky left-0 z-10 bg-base-100"></th>
                <th :for={role <- @roles} class="text-center text-xs">{SchoolRole.label(role)}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={right <- @rights} id={"right-#{right.key}"}>
                <th class="sticky left-0 z-10 bg-base-100 font-normal">{right.label}</th>
                <td :for={role <- @roles} class="text-center text-xs">
                  <%= case SchoolRole.cell(right, role) do %>
                    <% :yes -> %>
                      <.icon name="hero-check" class="size-4 text-primary" />
                    <% :no -> %>
                      <span class="text-base-content/70">—</span>
                    <% {:note, text} -> %>
                      <span class="text-base-content/80">{text}</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p id="teaching-footnote" class="text-xs text-base-content/70">
          {SchoolRole.teaching_footnote()}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
