defmodule TeacherAssistantWeb.School.SettingsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.{Permissions, Schools}
  alias TeacherAssistant.Accounts.{SchoolTypes, SchoolSubsystems, SchoolSectors, CameroonRegions}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type != :school do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      admin? = Permissions.admin?(scope)

      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:head?, Permissions.head?(scope))
       |> assign(:admin?, admin?)
       |> assign(:name_form, to_form(%{"name" => scope.current_workspace.name}, as: :school))
       |> assign(
         :year_form,
         to_form(%{"name" => "", "start_date" => "", "end_date" => ""}, as: :year)
       )
       |> allow_upload(:logo,
         accept: ~w(.png .jpg .jpeg),
         max_entries: 1,
         max_file_size: 2_000_000
       )
       |> load_years()
       |> then(fn socket -> if admin?, do: load_profile(socket), else: socket end)}
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

        <div :if={@admin?}>
          <.link navigate={~p"/school/periods"} class="link link-primary text-sm">
            {gettext("Emploi du temps — périodes")}
          </.link>
        </div>

        <div :if={@admin? and @profile_form} class="ta-leaf space-y-3">
          <h2 class="text-lg font-semibold">{gettext("Profil de l'école")}</h2>

          <.form
            for={@profile_form}
            id="school-profile-form"
            phx-submit="save_profile"
            class="space-y-3"
          >
            <div class="grid gap-2 sm:grid-cols-2">
              <.input field={@profile_form[:short_name]} label={gettext("Nom court")} />
              <.input
                type="select"
                field={@profile_form[:school_type]}
                label={gettext("Type d'établissement")}
                options={for t <- SchoolTypes.all(), do: {SchoolTypes.label(t), t}}
                prompt={gettext("Sélectionner un type")}
              />
              <.input
                type="select"
                field={@profile_form[:subsystem]}
                label={gettext("Sous-système")}
                options={for s <- SchoolSubsystems.all(), do: {SchoolSubsystems.label(s), s}}
                prompt={gettext("Sélectionner un sous-système")}
              />
              <.input
                type="select"
                field={@profile_form[:sector]}
                label={gettext("Secteur")}
                options={for s <- SchoolSectors.all(), do: {SchoolSectors.label(s), s}}
                prompt={gettext("Sélectionner un secteur")}
              />
              <.input
                type="select"
                field={@profile_form[:region]}
                label={gettext("Région")}
                options={for r <- CameroonRegions.all(), do: {CameroonRegions.label(r), r}}
                prompt={gettext("Sélectionner une région")}
              />
              <.input field={@profile_form[:department]} label={gettext("Département")} />
              <.input field={@profile_form[:town]} label={gettext("Ville")} />
              <.input field={@profile_form[:phone]} label={gettext("Téléphone")} />
              <.input field={@profile_form[:email]} label={gettext("Email")} />
              <.input field={@profile_form[:address]} label={gettext("Adresse")} />
              <.input
                field={@profile_form[:head_name]}
                label={gettext("Nom du chef d'établissement")}
              />
              <.input field={@profile_form[:motto]} label={gettext("Devise")} />
              <.input
                field={@profile_form[:registration_number]}
                label={gettext("Numéro d'autorisation")}
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </.form>

          <.form
            for={%{}}
            id="school-logo-form"
            phx-submit="save_logo"
            phx-change="validate_logo"
            multipart
            class="space-y-3"
          >
            <img
              :if={@profile.logo_path}
              src={~p"/school/logo"}
              alt={gettext("Logo de l'école")}
              class="h-16 w-16 rounded object-cover"
            />
            <.live_file_input upload={@uploads.logo} />
            <button type="submit" class="btn btn-secondary btn-sm">
              {gettext("Téléverser le logo")}
            </button>
          </.form>
        </div>

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

  def handle_event("save_profile", %{"profile" => attrs}, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) and socket.assigns.profile do
      case Schools.update_school_profile(socket.assigns.profile, attrs) do
        {:ok, _profile} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Profil de l'école mis à jour."))
           |> load_profile()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, gettext("Impossible de mettre à jour le profil."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_logo", _params, socket), do: {:noreply, socket}

  def handle_event("save_logo", _params, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) and socket.assigns.profile do
      uploads_dir = Application.fetch_env!(:teacher_assistant, :uploads_dir)
      workspace_id = scope.current_workspace.id

      uploaded =
        consume_uploaded_entries(socket, :logo, fn %{path: tmp}, entry ->
          ext = Path.extname(entry.client_name)
          filename = Ash.UUIDv7.generate() <> ext
          relative_path = Path.join(["school_logos", workspace_id, filename])
          dest = Path.join(uploads_dir, relative_path)

          dest |> Path.dirname() |> File.mkdir_p!()
          File.cp!(tmp, dest)

          {:ok, relative_path}
        end)

      case uploaded do
        [relative_path] ->
          case Schools.update_school_profile(socket.assigns.profile, %{logo_path: relative_path}) do
            {:ok, _profile} ->
              {:noreply,
               socket
               |> put_flash(:info, gettext("Logo mis à jour."))
               |> load_profile()}

            {:error, _changeset} ->
              {:noreply,
               put_flash(socket, :error, gettext("Impossible de mettre à jour le logo."))}
          end

        [] ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_years(socket) do
    scope = socket.assigns.scope
    assign(socket, :years, Academics.list_academic_years(scope.current_workspace))
  end

  defp load_profile(socket) do
    scope = socket.assigns.scope

    case Schools.fetch_school_profile(scope.current_workspace) do
      {:ok, profile} ->
        socket
        |> assign(:profile, profile)
        |> assign(:profile_form, to_form(profile_params(profile), as: :profile))

      {:error, _} ->
        socket
        |> assign(:profile, nil)
        |> assign(:profile_form, nil)
    end
  end

  defp profile_params(profile) do
    %{
      "short_name" => profile.short_name,
      "school_type" => profile.school_type,
      "subsystem" => profile.subsystem,
      "sector" => profile.sector,
      "region" => profile.region,
      "department" => profile.department,
      "town" => profile.town,
      "phone" => profile.phone,
      "email" => profile.email,
      "address" => profile.address,
      "head_name" => profile.head_name,
      "motto" => profile.motto,
      "registration_number" => profile.registration_number
    }
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
