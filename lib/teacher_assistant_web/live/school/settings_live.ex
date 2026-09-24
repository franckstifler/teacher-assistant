defmodule TeacherAssistantWeb.School.SettingsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{AcademicYear, Subject, SubjectCategory}
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts.{Permissions}
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      admin? = Permissions.admin?(scope)

      socket =
        socket
        |> assign(:scope, scope)
        |> assign(:head?, Permissions.head?(scope))
        |> assign(:admin?, admin?)
        |> assign(:name_form, name_form(scope.current_workspace))
        |> assign(:subjects, Curriculum.list_subjects(scope.current_workspace))
        |> assign(:subject_form, subject_form(scope.current_workspace.id))
        |> allow_upload(:logo,
          accept: ~w(.png .jpg .jpeg),
          max_entries: 1,
          max_file_size: 2_000_000
        )
        # `load_years/1` must run before `year_form/2` is built: the form's
        # `active` flag (see `year_form/2`) is derived from whether any years
        # already exist.
        |> load_years()

      socket =
        socket
        |> assign(:year_form, year_form(scope.current_workspace.id, socket.assigns.years == []))
        |> then(fn socket -> if admin?, do: load_profile(socket), else: socket end)

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-settings-page" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Paramètres")} />

        <nav class="flex flex-wrap gap-3 border-b border-base-300 pb-3 text-sm">
          <a href="#profil" class="link link-hover">{gettext("Profil")}</a>
          <a href="#annee" class="link link-hover">{gettext("Année scolaire")}</a>
          <a href="#matieres" class="link link-hover">{gettext("Matières")}</a>
          <a href="#emploi" class="link link-hover">{gettext("Emploi du temps")}</a>
          <.link navigate={~p"/school/classes"} class="link link-hover">{gettext("Classes")}</.link>
        </nav>

        <section id="profil" class="space-y-6">
          <.form
            :if={@head?}
            for={@name_form}
            id="school-settings"
            phx-change="validate_name"
            phx-submit="save"
            class="ta-leaf space-y-3"
          >
            <.input field={@name_form[:name]} type="text" label={gettext("Nom de l'école")} />
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </.form>

          <div :if={@admin? and @profile_form} class="ta-leaf space-y-3">
            <h2 class="text-lg font-semibold">{gettext("Profil de l'école")}</h2>

            <.form
              for={@profile_form}
              id="school-profile-form"
              phx-change="validate_profile"
              phx-submit="save_profile"
              class="space-y-3"
            >
              <div class="grid gap-2 sm:grid-cols-2">
                <.input field={@profile_form[:short_name]} label={gettext("Nom court")} />
                <.input
                  type="select"
                  field={@profile_form[:school_type]}
                  label={gettext("Type d'établissement")}
                  options={for t <- SchoolType.values(), do: {SchoolType.label(t), t}}
                  prompt={gettext("Sélectionner un type")}
                />
                <.input
                  type="select"
                  field={@profile_form[:subsystem]}
                  label={gettext("Sous-système")}
                  options={for s <- SchoolSubsystem.values(), do: {SchoolSubsystem.label(s), s}}
                  prompt={gettext("Sélectionner un sous-système")}
                />
                <.input
                  type="select"
                  field={@profile_form[:sector]}
                  label={gettext("Secteur")}
                  options={for s <- SchoolSector.values(), do: {SchoolSector.label(s), s}}
                  prompt={gettext("Sélectionner un secteur")}
                />
                <.input
                  type="select"
                  field={@profile_form[:region]}
                  label={gettext("Région")}
                  options={for r <- CameroonRegion.values(), do: {CameroonRegion.label(r), r}}
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
        </section>

        <section :if={@admin?} id="annee" class="space-y-4">
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

          <div
            :if={@active_year && @active_sequences == []}
            id={"year-no-calendar-#{@active_year.id}"}
            class="rounded-box border border-warning/40 bg-warning/10 p-4 text-sm"
          >
            <p>
              {gettext("L'année %{name} n'a pas encore de trimestres ni de séquences.",
                name: @active_year.name
              )}
            </p>
            <button
              id={"generate-calendar-#{@active_year.id}"}
              type="button"
              class="btn btn-primary btn-sm mt-2"
              phx-click="generate_calendar"
              phx-value-id={@active_year.id}
            >
              {gettext("Générer le calendrier")}
            </button>
          </div>

          <div
            :if={@active_year && @active_sequences != []}
            id={"year-calendar-#{@active_year.id}"}
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h3 class="text-sm font-semibold">
              {gettext("Trimestres et séquences")} · {@active_year.name}
            </h3>
            <p class="mt-1 text-xs text-base-content/70">
              {gettext(
                "Calendrier généré à la création de l'année. Les dates seront modifiables prochainement."
              )}
            </p>
            <ul class="mt-3 grid gap-1 text-sm sm:grid-cols-2">
              <li
                :for={seq <- @active_sequences}
                id={"sequence-#{seq.id}"}
                class="flex justify-between gap-3"
              >
                <span>
                  <span class="text-base-content/60">
                    {gettext("Trimestre %{n}", n: div(seq.number - 1, 2) + 1)} ·
                  </span>
                  {gettext("Séquence %{n}", n: seq.number)}
                </span>
                <span class="ta-num text-base-content/70">
                  {Calendar.strftime(seq.start_date, "%d/%m/%Y")} → {Calendar.strftime(
                    seq.end_date,
                    "%d/%m/%Y"
                  )}
                </span>
              </li>
            </ul>
          </div>

          <.empty_state
            :if={@years == []}
            icon="hero-calendar"
            title={gettext("No academic years yet")}
          />

          <div class="ta-leaf space-y-3">
            <h3 class="text-sm font-semibold">{gettext("Create an academic year")}</h3>
            <.form
              for={@year_form}
              id="year-form"
              phx-change="validate_year"
              phx-submit="create_year"
              class="space-y-2"
            >
              <div class="grid gap-2 sm:grid-cols-3">
                <.input field={@year_form[:name]} label={gettext("Name")} />
                <.input field={@year_form[:start_date]} type="date" label={gettext("Start date")} />
                <.input field={@year_form[:end_date]} type="date" label={gettext("End date")} />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Create")}</button>
            </.form>
          </div>
        </section>

        <section :if={@admin?} id="matieres" class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Matières")}</h2>

          <div class="overflow-x-auto">
            <table :if={@subjects != []} id="subjects-table" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Nom")}</th>
                  <th>{gettext("Coefficient")}</th>
                  <th>{gettext("Catégorie")}</th>
                  <th>{gettext("Statut")}</th>
                  <th><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @subjects} id={"subject-row-#{s.id}"}>
                  <td colspan="5">
                    <.form
                      for={
                        AshPhoenix.Form.for_update(s, :update,
                          as: "subject_edit",
                          tenant: s.workspace_id
                        )
                        |> to_form()
                      }
                      id={"subject-edit-form-#{s.id}"}
                      phx-submit="update_subject"
                      class="grid items-end gap-2 sm:grid-cols-6"
                    >
                      <input type="hidden" name="subject_id" value={s.id} />
                      <.input name="subject_edit[name]" value={s.name} label={gettext("Nom")} />
                      <.input
                        name="subject_edit[default_coefficient]"
                        value={s.default_coefficient}
                        label={gettext("Coefficient")}
                      />
                      <.input
                        name="subject_edit[category]"
                        type="select"
                        value={to_string(s.category)}
                        options={[
                          {SubjectCategory.label(:general), "general"},
                          {SubjectCategory.label(:language), "language"},
                          {SubjectCategory.label(:technical), "technical"}
                        ]}
                        label={gettext("Catégorie")}
                      />
                      <div>
                        <span :if={s.active?} class="badge badge-primary">{gettext("Active")}</span>
                        <span :if={!s.active?} class="badge badge-ghost">
                          {gettext("Inactive")}
                        </span>
                      </div>
                      <div class="flex flex-wrap gap-2">
                        <button type="submit" class="btn btn-primary btn-sm">
                          {gettext("Enregistrer")}
                        </button>
                        <button
                          type="button"
                          id={"subject-toggle-active-#{s.id}"}
                          class="btn btn-ghost btn-sm"
                          phx-click="toggle_subject_active"
                          phx-value-id={s.id}
                        >
                          {if s.active?, do: gettext("Désactiver"), else: gettext("Réactiver")}
                        </button>
                        <button
                          type="button"
                          id={"subject-delete-#{s.id}"}
                          phx-click="delete_subject"
                          phx-value-id={s.id}
                          class="btn btn-ghost btn-sm text-error"
                        >
                          <span class="sr-only">{s.name}</span>
                          {gettext("Supprimer")}
                        </button>
                      </div>
                    </.form>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.empty_state
            :if={@subjects == []}
            icon="hero-book-open"
            title={gettext("Aucune matière pour l'instant")}
          />

          <div class="ta-leaf space-y-3">
            <h3 class="text-sm font-semibold">{gettext("Ajouter une matière")}</h3>
            <.form
              for={@subject_form}
              id="subject-form"
              phx-change="validate_subject"
              phx-submit="create_subject"
              class="flex flex-wrap items-end gap-2"
            >
              <.input field={@subject_form[:name]} label={gettext("Nom de la matière")} />
              <.input
                field={@subject_form[:category]}
                type="select"
                label={gettext("Catégorie")}
                options={[
                  {SubjectCategory.label(:general), "general"},
                  {SubjectCategory.label(:language), "language"},
                  {SubjectCategory.label(:technical), "technical"}
                ]}
              />
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter")}</button>
            </.form>
          </div>
        </section>

        <section :if={@admin?} id="emploi">
          <.link navigate={~p"/school/periods"} class="link link-primary text-sm">
            {gettext("Emploi du temps — périodes")}
          </.link>
        </section>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("validate_name", %{"school" => params}, socket) do
    {:noreply,
     assign(socket, :name_form, AshPhoenix.Form.validate(socket.assigns.name_form, params))}
  end

  def handle_event("save", %{"school" => params}, socket) do
    scope = socket.assigns.scope

    if Permissions.head?(scope) do
      case AshPhoenix.Form.submit(socket.assigns.name_form, params: params) do
        {:ok, school} ->
          new_scope = %{scope | current_workspace: school}

          {:noreply,
           socket
           |> assign(:scope, new_scope)
           |> assign(:current_scope, new_scope)
           |> assign(:name_form, name_form(school))
           |> put_flash(:info, gettext("École renommée avec succès."))}

        {:error, form} ->
          {:noreply,
           socket
           |> assign(:name_form, form)
           |> put_flash(:error, gettext("Impossible de renommer l'école."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_year", %{"year" => params}, socket) do
    {:noreply,
     assign(socket, :year_form, AshPhoenix.Form.validate(socket.assigns.year_form, params))}
  end

  def handle_event("generate_calendar", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with true <- Permissions.admin?(scope),
         {:ok, year} <- Organization.get_academic_year(id, scope.current_workspace),
         :ok <- Organization.build_default_calendar(year) do
      {:noreply, socket |> load_years() |> put_flash(:info, gettext("Calendrier généré."))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_year", %{"year" => params}, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) do
      case AshPhoenix.Form.submit(socket.assigns.year_form, params: params) do
        {:ok, year} ->
          :ok = Organization.build_default_calendar(year)
          :ok = TeacherAssistant.Attendance.build_default_periods(scope.current_workspace)
          TeacherAssistant.Academics.Seeding.seed_starter_classes(scope.current_workspace, year)

          socket = load_years(socket)

          {:noreply,
           socket
           |> put_flash(:info, gettext("Année scolaire créée."))
           |> assign(
             :year_form,
             year_form(scope.current_workspace.id, socket.assigns.years == [])
           )}

        {:error, form} ->
          {:noreply,
           socket
           |> assign(:year_form, form)
           |> put_flash(:error, gettext("Impossible de créer l'année scolaire."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("activate_year", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with true <- Permissions.admin?(scope),
         {:ok, year} <- Organization.get_academic_year(id, scope.current_workspace),
         {:ok, _} <- Organization.activate_academic_year(year) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Année scolaire activée."))
       |> load_years()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("validate_subject", %{"subject" => params}, socket) do
    {:noreply,
     assign(socket, :subject_form, AshPhoenix.Form.validate(socket.assigns.subject_form, params))}
  end

  def handle_event("create_subject", %{"subject" => params}, socket) do
    scope = socket.assigns.scope
    ws = scope.current_workspace

    if Permissions.admin?(scope) do
      case AshPhoenix.Form.submit(socket.assigns.subject_form, params: params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:subjects, Curriculum.list_subjects(ws))
           |> assign(:subject_form, subject_form(ws.id))}

        {:error, form} ->
          {:noreply, assign(socket, :subject_form, form)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_subject", %{"id" => id}, socket) do
    scope = socket.assigns.scope
    ws = scope.current_workspace

    if Permissions.admin?(scope) do
      subject = Enum.find(socket.assigns.subjects, &(&1.id == id))
      if subject, do: Curriculum.delete_subject(subject, tenant: subject.workspace_id)
      {:noreply, assign(socket, :subjects, Curriculum.list_subjects(ws))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_subject", %{"subject_id" => id, "subject_edit" => params}, socket) do
    scope = socket.assigns.scope
    ws = scope.current_workspace

    with true <- Permissions.admin?(scope),
         %{} = subject <- Enum.find(socket.assigns.subjects, &(&1.id == id)),
         {:ok, coefficient} <- Curriculum.parse_coefficient(params["default_coefficient"]) do
      form =
        AshPhoenix.Form.for_update(subject, :update,
          as: "subject_edit",
          tenant: subject.workspace_id
        )

      # `name` trims at the Subject type level (same as create and the seeder),
      # so no per-handler trim is needed here — that asymmetry is now gone.
      submit_params = Map.put(params, "default_coefficient", coefficient)

      case AshPhoenix.Form.submit(form, params: submit_params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:subjects, Curriculum.list_subjects(ws))
           |> put_flash(:info, gettext("Matière mise à jour."))}

        {:error, _form} ->
          {:noreply,
           put_flash(socket, :error, gettext("Impossible de mettre à jour la matière."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_subject_active", %{"id" => id}, socket) do
    scope = socket.assigns.scope
    ws = scope.current_workspace

    with true <- Permissions.admin?(scope),
         %{} = subject <- Enum.find(socket.assigns.subjects, &(&1.id == id)) do
      result =
        if subject.active?,
          do: Curriculum.deactivate_subject(subject, tenant: subject.workspace_id),
          else: Curriculum.update_subject(subject, %{active?: true})

      case result do
        {:ok, _} ->
          {:noreply, assign(socket, :subjects, Curriculum.list_subjects(ws))}

        _ ->
          {:noreply,
           put_flash(socket, :error, gettext("Impossible de mettre à jour la matière."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("validate_profile", %{"profile" => params}, socket) do
    if socket.assigns.profile_form do
      {:noreply,
       assign(
         socket,
         :profile_form,
         AshPhoenix.Form.validate(socket.assigns.profile_form, params)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_profile", %{"profile" => attrs}, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) and socket.assigns.profile do
      case AshPhoenix.Form.submit(socket.assigns.profile_form, params: attrs) do
        {:ok, _profile} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Profil de l'école mis à jour."))
           |> load_profile()}

        {:error, form} ->
          {:noreply,
           socket
           |> assign(:profile_form, form)
           |> put_flash(:error, gettext("Impossible de mettre à jour le profil."))}
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
          case Accounts.update_school_profile(socket.assigns.profile, %{logo_path: relative_path}) do
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
    years = Organization.list_academic_years(scope.current_workspace)
    active_year = Enum.find(years, & &1.active)

    socket
    |> assign(:years, years)
    |> assign(:active_year, active_year)
    |> assign(
      :active_sequences,
      if(active_year, do: Organization.list_sequences(active_year), else: [])
    )
  end

  defp load_profile(socket) do
    scope = socket.assigns.scope

    case Accounts.fetch_school_profile(scope.current_workspace) do
      {:ok, profile} ->
        socket
        |> assign(:profile, profile)
        |> assign(
          :profile_form,
          AshPhoenix.Form.for_update(profile, :update, as: "profile") |> to_form()
        )

      {:error, _} ->
        socket
        |> assign(:profile, nil)
        |> assign(:profile_form, nil)
    end
  end

  defp name_form(workspace) do
    workspace |> AshPhoenix.Form.for_update(:update, as: "school") |> to_form()
  end

  # `AcademicYear` is tenant-scoped to the workspace (attribute multitenancy);
  # `workspace_id` is no longer an acceptable create attribute, it's derived
  # from the form's `tenant:`. `active` is still server-controlled (never
  # user input), set on the changeset at build time via `prepare_source` —
  # not merged into the submitted params at submit time. Only the first year
  # of a workspace is created active (the `:create_for_workspace` action
  # deactivates any other active year), so `active?` is a *live* value: it
  # flips from `true` to `false` the moment the first year exists. Callers
  # must rebuild the form — via this helper — on mount and again right after
  # a successful year creation (see `handle_event("create_year", ...)`).
  defp year_form(workspace_id, active?) do
    AcademicYear
    |> AshPhoenix.Form.for_create(:create_for_workspace,
      as: "year",
      tenant: workspace_id,
      prepare_source: fn changeset ->
        Ash.Changeset.change_attribute(changeset, :active, active?)
      end
    )
    |> to_form()
  end

  # `Subject` is tenant-scoped to the workspace (attribute multitenancy);
  # `workspace_id` is no longer an acceptable create attribute, it's derived
  # from the form's `tenant:`. It's stable for the life of this LiveView
  # (renaming the school doesn't change its id), so no mid-session rebuild is
  # needed beyond the fresh scaffold assigned after each successful create.
  defp subject_form(workspace_id) do
    Subject
    |> AshPhoenix.Form.for_create(:create, as: "subject", tenant: workspace_id)
    |> to_form()
  end
end
