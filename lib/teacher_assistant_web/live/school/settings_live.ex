defmodule TeacherAssistantWeb.School.SettingsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.{Permissions, Schools}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type != :school do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:head?, Permissions.head?(scope))
       |> assign(:admin?, Permissions.admin?(scope))
       |> assign(:name_form, to_form(%{"name" => scope.current_workspace.name}, as: :school))
       |> assign(
         :year_form,
         to_form(%{"name" => "", "start_date" => "", "end_date" => ""}, as: :year)
       )
       |> load_years()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-settings-page" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Paramètres")} />

        <.form
          :if={@head?}
          for={@name_form}
          id="school-settings"
          phx-submit="save"
          class="ta-leaf space-y-3"
        >
          <.input field={@name_form[:name]} type="text" label={gettext("Nom de l'école")} />
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>

        <div :if={@admin?} class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Année scolaire")}</h2>

          <div class="overflow-x-auto">
            <table id="years-table" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Nom")}</th>
                  <th>{gettext("Début")}</th>
                  <th>{gettext("Fin")}</th>
                  <th>{gettext("Statut")}</th>
                  <th><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={year <- @years} id={"year-row-#{year.id}"}>
                  <td>{year.name}</td>
                  <td>{year.start_date}</td>
                  <td>{year.end_date}</td>
                  <td>
                    <span :if={year.active} class="badge badge-primary">{gettext("Active")}</span>
                    <span :if={!year.active} class="badge badge-ghost">{gettext("Inactive")}</span>
                  </td>
                  <td>
                    <button
                      :if={!year.active}
                      id={"year-activate-#{year.id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="activate_year"
                      phx-value-id={year.id}
                    >
                      {gettext("Activer")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.empty_state
            :if={@years == []}
            icon="hero-calendar"
            title={gettext("No academic years yet")}
          />

          <div class="ta-leaf space-y-3">
            <h3 class="text-sm font-semibold">{gettext("Create an academic year")}</h3>
            <.form for={@year_form} id="year-form" phx-submit="create_year" class="space-y-2">
              <div class="grid gap-2 sm:grid-cols-3">
                <.input field={@year_form[:name]} label={gettext("Name")} />
                <.input field={@year_form[:start_date]} type="date" label={gettext("Start date")} />
                <.input field={@year_form[:end_date]} type="date" label={gettext("End date")} />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Create")}</button>
            </.form>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("save", %{"school" => %{"name" => name}}, socket) do
    scope = socket.assigns.scope

    if Permissions.head?(scope) do
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
    else
      {:noreply, socket}
    end
  end

  def handle_event("create_year", %{"year" => params}, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) do
      attrs = %{
        name: params["name"],
        start_date: parse_date(params["start_date"]),
        end_date: parse_date(params["end_date"]),
        active: socket.assigns.years == []
      }

      case Academics.create_academic_year(scope.current_workspace, attrs) do
        {:ok, _year} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Année scolaire créée."))
           |> load_years()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Impossible de créer l'année scolaire."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("activate_year", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with true <- Permissions.admin?(scope),
         {:ok, year} <- Academics.get_academic_year(id),
         true <- year.workspace_id == scope.current_workspace.id,
         {:ok, _} <- Academics.activate_academic_year(year) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Année scolaire activée."))
       |> load_years()}
    else
      _ -> {:noreply, socket}
    end
  end

  defp load_years(socket) do
    scope = socket.assigns.scope
    assign(socket, :years, Academics.list_academic_years(scope.current_workspace))
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
