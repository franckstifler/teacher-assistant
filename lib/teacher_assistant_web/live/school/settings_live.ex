defmodule TeacherAssistantWeb.School.SettingsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.{Permissions, Schools}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Permissions.head?(scope) do
      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:name_form, to_form(%{"name" => scope.current_workspace.name}, as: :school))}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-settings-page" class="space-y-4">
        <.page_header eyebrow={gettext("École")} title={gettext("Paramètres")} />

        <.form for={@name_form} id="school-settings" phx-submit="save" class="ta-leaf space-y-3">
          <.input field={@name_form[:name]} type="text" label={gettext("Nom de l'école")} />
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("save", %{"school" => %{"name" => name}}, socket) do
    scope = socket.assigns.scope

    case Schools.rename_school(scope.current_workspace, name) do
      {:ok, school} ->
        new_scope = %{scope | current_workspace: school}

        {:noreply,
         socket
         |> assign(:scope, new_scope)
         |> assign(:current_scope, new_scope)
         |> assign(:name_form, to_form(%{"name" => school.name}, as: :school))
         |> put_flash(:info, gettext("École renommée avec succès."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Impossible de renommer l'école."))}
    end
  end
end
