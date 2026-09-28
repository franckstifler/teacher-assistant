defmodule TeacherAssistantWeb.School.SettingsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{AcademicYear, BulletinGroup, Subject}
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      socket =
        socket
        |> assign(:scope, scope)
        |> assign(:can_manage_periods?, TeacherAssistant.Attendance.can_manage_periods?(scope))
        |> assign(:can_manage_calendar?, Organization.can_manage_calendar?(scope))
        |> assign(calendar_errors: %{}, calendar_params: %{})
        |> assign(:can_rename_school?, Organization.can_rename_school?(scope))
        |> assign(:can_manage_subjects?, Curriculum.can_manage_subjects?(scope))
        |> assign(:name_form, name_form(scope))
        |> assign(:subjects, Curriculum.list_subjects(scope))
        |> assign(:subject_form, subject_form(scope))
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
        |> assign(:year_form, year_form(scope, socket.assigns.years == []))
        |> load_profile()

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
            :if={@can_rename_school?}
            for={@name_form}
            id="school-settings"
            phx-change="validate_name"
            phx-submit="save"
            class="ta-leaf space-y-3"
          >
            <.input field={@name_form[:name]} type="text" label={gettext("Nom de l'école")} />
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </.form>

          <div :if={@can_edit_profile? and @profile_form} class="ta-leaf space-y-3">
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

        <section :if={@can_manage_calendar?} id="annee" class="space-y-4">
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
                "Sans date limite, la saisie des notes ferme %{days} jours après la fin de la séquence.",
                days: TeacherAssistant.Academics.Reference.entry_grace_days()
              )}
            </p>

            <.form
              for={to_form(%{}, as: :calendar)}
              id="calendar-form"
              phx-submit="save_calendar"
              class="mt-3 space-y-3"
            >
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{gettext("Séquence")}</th>
                      <th>{gettext("Début")}</th>
                      <th>{gettext("Fin")}</th>
                      <th>{gettext("Limite de saisie")}</th>
                      <th>{gettext("Conseil de classe")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={seq <- @active_sequences} id={"sequence-#{seq.id}"} class="align-top">
                      <td class="whitespace-nowrap">
                        <span class="text-base-content/60">
                          {gettext("Trimestre %{n}", n: seq.term.position)} ·
                        </span>
                        {gettext("Séquence %{n}", n: seq.number)}
                      </td>
                      <td :for={field <- [:start_date, :end_date, :entry_deadline]}>
                        <.input
                          type="date"
                          name={"calendar[sequences][#{seq.id}][#{field}]"}
                          value={
                            calendar_value(
                              @calendar_params,
                              "sequences",
                              seq.id,
                              field,
                              Map.get(seq, field)
                            )
                          }
                          disabled={!@can_manage_calendar?}
                          errors={calendar_errors(@calendar_errors, seq.id, field)}
                        />
                        <span
                          :if={field == :entry_deadline and is_nil(seq.entry_deadline)}
                          class="ta-num text-xs text-base-content/60"
                        >
                          {gettext("Par défaut : %{date}",
                            date: Calendar.strftime(seq.grade_entry_deadline, "%d/%m/%Y")
                          )}
                        </span>
                      </td>
                      <td>
                        <.input
                          :if={seq.position_in_term == 2}
                          type="date"
                          name={"calendar[terms][#{seq.term_id}][class_council_date]"}
                          value={
                            calendar_value(
                              @calendar_params,
                              "terms",
                              seq.term_id,
                              :class_council_date,
                              seq.term.class_council_date
                            )
                          }
                          disabled={!@can_manage_calendar?}
                          errors={calendar_errors(@calendar_errors, seq.term_id, :class_council_date)}
                        />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <button :if={@can_manage_calendar?} type="submit" class="btn btn-primary btn-sm">
                {gettext("Enregistrer le calendrier")}
              </button>
            </.form>
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

        <section :if={@can_manage_subjects?} id="matieres" class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Matières")}</h2>

          <.link
            id="coefficients-link"
            navigate={~p"/school/settings/coefficients"}
            class="link link-primary text-sm"
          >
            {gettext("Coefficients par niveau et groupes du bulletin")}
          </.link>

          <div class="overflow-x-auto">
            <table :if={@subjects != []} id="subjects-table" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Nom")}</th>
                  <th>{gettext("Coefficient")}</th>
                  <th>{gettext("Groupe du bulletin")}</th>
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
                          scope: @scope
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
                        name="subject_edit[bulletin_group]"
                        type="select"
                        value={to_string(s.bulletin_group)}
                        options={bulletin_group_options()}
                        label={gettext("Groupe du bulletin")}
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
                field={@subject_form[:bulletin_group]}
                type="select"
                label={gettext("Groupe du bulletin")}
                options={bulletin_group_options()}
              />
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter")}</button>
            </.form>
          </div>
        </section>

        <section :if={@can_manage_periods?} id="emploi">
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

    case AshPhoenix.Form.submit(socket.assigns.name_form, params: params) do
      {:ok, school} ->
        new_scope = %{scope | current_workspace: school}

        {:noreply,
         socket
         |> assign(:scope, new_scope)
         |> assign(:current_scope, new_scope)
         |> assign(:name_form, name_form(new_scope))
         |> put_flash(:info, gettext("École renommée avec succès."))}

      {:error, form} ->
        if Authz.forbidden_form?(form) do
          {:noreply, Authz.put_not_allowed(socket)}
        else
          {:noreply,
           socket
           |> assign(:name_form, form)
           |> put_flash(:error, gettext("Impossible de renommer l'école."))}
        end
    end
  end

  def handle_event("validate_year", %{"year" => params}, socket) do
    {:noreply,
     assign(socket, :year_form, AshPhoenix.Form.validate(socket.assigns.year_form, params))}
  end

  def handle_event("save_calendar", %{"calendar" => params}, socket) do
    case Organization.update_calendar(socket.assigns.scope, socket.assigns.active_year, params) do
      :ok ->
        {:noreply,
         socket
         |> assign(calendar_errors: %{}, calendar_params: %{})
         |> load_years()
         |> put_flash(:info, gettext("Calendrier enregistré."))}

      {:error, {:invalid, errors}} ->
        {:noreply,
         socket
         |> assign(calendar_errors: errors, calendar_params: params)
         |> put_flash(
           :error,
           gettext("Calendrier non enregistré : corrigez les dates signalées.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Calendrier non enregistré."))}
    end
  end

  def handle_event("generate_calendar", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with {:ok, year} <- Organization.get_academic_year(scope, id),
         :ok <- Organization.build_default_calendar(scope, year) do
      {:noreply, socket |> load_years() |> put_flash(:info, gettext("Calendrier généré."))}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_year", %{"year" => params}, socket) do
    scope = socket.assigns.scope

    case AshPhoenix.Form.submit(socket.assigns.year_form, params: params) do
      {:ok, year} ->
        :ok = Organization.build_default_calendar(scope, year)
        :ok = TeacherAssistant.Attendance.build_default_periods(scope)
        TeacherAssistant.Academics.Seeding.seed_starter_classes(scope, year)

        socket = load_years(socket)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Année scolaire créée."))
         |> assign(
           :year_form,
           year_form(scope, socket.assigns.years == [])
         )}

      {:error, form} ->
        if Authz.forbidden_form?(form) do
          {:noreply, Authz.put_not_allowed(socket)}
        else
          {:noreply,
           socket
           |> assign(:year_form, form)
           |> put_flash(:error, gettext("Impossible de créer l'année scolaire."))}
        end
    end
  end

  def handle_event("activate_year", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with {:ok, year} <- Organization.get_academic_year(scope, id),
         {:ok, _} <- Organization.activate_academic_year(scope, year) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Année scolaire activée."))
       |> load_years()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("validate_subject", %{"subject" => params}, socket) do
    {:noreply,
     assign(socket, :subject_form, AshPhoenix.Form.validate(socket.assigns.subject_form, params))}
  end

  def handle_event("create_subject", %{"subject" => params}, socket) do
    scope = socket.assigns.scope

    case AshPhoenix.Form.submit(socket.assigns.subject_form, params: params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:subjects, Curriculum.list_subjects(scope))
         |> assign(:subject_form, subject_form(scope))}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:noreply, Authz.put_not_allowed(socket)},
          else: {:noreply, assign(socket, :subject_form, form)}
    end
  end

  def handle_event("delete_subject", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = subject <- Enum.find(socket.assigns.subjects, &(&1.id == id)) do
      case Curriculum.delete_subject(subject, scope: scope) do
        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Matière utilisée par des classes : désactivez-la plutôt.")
           )}

        _ ->
          {:noreply, assign(socket, :subjects, Curriculum.list_subjects(scope))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_subject", %{"subject_id" => id, "subject_edit" => params}, socket) do
    scope = socket.assigns.scope

    with %{} = subject <- Enum.find(socket.assigns.subjects, &(&1.id == id)),
         {:ok, coefficient} <- Curriculum.parse_coefficient(params["default_coefficient"]) do
      form =
        AshPhoenix.Form.for_update(subject, :update,
          as: "subject_edit",
          scope: scope
        )

      # `name` trims at the Subject type level (same as create and the seeder),
      # so no per-handler trim is needed here — that asymmetry is now gone.
      submit_params = Map.put(params, "default_coefficient", coefficient)

      case AshPhoenix.Form.submit(form, params: submit_params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:subjects, Curriculum.list_subjects(scope))
           |> put_flash(:info, gettext("Matière mise à jour."))}

        {:error, form} ->
          if Authz.forbidden_form?(form),
            do: {:noreply, Authz.put_not_allowed(socket)},
            else:
              {:noreply,
               put_flash(socket, :error, gettext("Impossible de mettre à jour la matière."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_subject_active", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = subject <- Enum.find(socket.assigns.subjects, &(&1.id == id)) do
      result =
        if subject.active?,
          do: Curriculum.deactivate_subject(subject, scope: scope),
          else: Curriculum.update_subject(scope, subject, %{active?: true})

      case result do
        {:ok, _} ->
          {:noreply, assign(socket, :subjects, Curriculum.list_subjects(scope))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

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
    if socket.assigns.profile do
      case AshPhoenix.Form.submit(socket.assigns.profile_form, params: attrs) do
        {:ok, _profile} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Profil de l'école mis à jour."))
           |> load_profile()}

        {:error, form} ->
          if Authz.forbidden_form?(form) do
            {:noreply, Authz.put_not_allowed(socket)}
          else
            {:noreply,
             socket
             |> assign(:profile_form, form)
             |> put_flash(:error, gettext("Impossible de mettre à jour le profil."))}
          end
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_logo", _params, socket), do: {:noreply, socket}

  def handle_event("save_logo", _params, socket) do
    scope = socket.assigns.scope

    # The capability gates the file write itself (a side effect outside the
    # data layer); the profile update below is still policy-checked.
    if socket.assigns.can_edit_profile? and socket.assigns.profile do
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
          case Accounts.update_school_profile(socket.assigns.profile, %{logo_path: relative_path},
                 scope: scope
               ) do
            {:ok, _profile} ->
              {:noreply,
               socket
               |> put_flash(:info, gettext("Logo mis à jour."))
               |> load_profile()}

            {:error, %Ash.Error.Forbidden{}} ->
              {:noreply, Authz.put_not_allowed(socket)}

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
    years = Organization.list_academic_years(scope)
    active_year = Enum.find(years, & &1.active)

    socket
    |> assign(:years, years)
    |> assign(:active_year, active_year)
    |> assign(
      :active_sequences,
      if(active_year, do: Organization.list_sequences(scope, active_year), else: [])
    )
  end

  defp load_profile(socket) do
    scope = socket.assigns.scope

    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} ->
        socket
        |> assign(:profile, profile)
        |> assign(:can_edit_profile?, Accounts.can_edit_profile?(scope, profile))
        |> assign(
          :profile_form,
          AshPhoenix.Form.for_update(profile, :update, as: "profile", scope: scope) |> to_form()
        )

      {:error, _} ->
        socket
        |> assign(:profile, nil)
        |> assign(:can_edit_profile?, false)
        |> assign(:profile_form, nil)
    end
  end

  defp name_form(scope) do
    scope.current_workspace
    |> AshPhoenix.Form.for_update(:update, as: "school", scope: scope)
    |> to_form()
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
  defp year_form(scope, active?) do
    AcademicYear
    |> AshPhoenix.Form.for_create(:create_for_workspace,
      as: "year",
      scope: scope,
      prepare_source: fn changeset ->
        Ash.Changeset.change_attribute(changeset, :active, active?)
      end
    )
    |> to_form()
  end

  # `Subject` is tenant-scoped to the workspace (attribute multitenancy);
  # the id is derived from the form's `scope:`. It's stable for the life of
  # this LiveView (renaming the school doesn't change its id), so no
  # mid-session rebuild is needed beyond the fresh scaffold assigned after
  # each successful create.
  defp subject_form(scope) do
    Subject
    |> AshPhoenix.Form.for_create(:create, as: "subject", scope: scope)
    |> to_form()
  end

  # The submitted value after a rejected save (so the manager's input is kept),
  # otherwise the stored date.
  defp calendar_value(params, kind, id, field, stored) do
    get_in(params, [kind, id, Atom.to_string(field)]) || stored
  end

  defp calendar_errors(errors, id, field) do
    for {^field, code} <- Map.get(errors, id, []), do: calendar_error_text(code)
  end

  defp calendar_error_text(:required), do: gettext("Date obligatoire.")
  defp calendar_error_text(:invalid_date), do: gettext("Date invalide.")
  defp calendar_error_text(:end_before_start), do: gettext("La fin est avant le début.")
  defp calendar_error_text(:outside_year), do: gettext("En dehors de l'année scolaire.")

  defp calendar_error_text(:overlaps_previous),
    do: gettext("Commence avant la fin de la séquence précédente.")

  defp calendar_error_text(:deadline_before_end),
    do: gettext("La limite de saisie est avant la fin de la séquence.")

  defp calendar_error_text(:council_before_term_end),
    do: gettext("Le conseil est avant la fin du trimestre.")

  defp bulletin_group_options,
    do: for(g <- BulletinGroup.values(), do: {BulletinGroup.label(g), to_string(g)})
end
