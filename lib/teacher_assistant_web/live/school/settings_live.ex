defmodule TeacherAssistantWeb.School.SettingsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{BulletinGroup, Subject}
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion}
  alias TeacherAssistantWeb.{Dates, Numbers}

  import TeacherAssistantWeb.Drawer

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
        |> assign(:editing_subject, nil)
        |> allow_upload(:logo,
          accept: ~w(.png .jpg .jpeg),
          max_entries: 1,
          max_file_size: 2_000_000
        )
        |> load_years()
        |> load_profile()

      {:ok, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, page_title(socket.assigns.live_action))}
  end

  defp page_title(:profile), do: gettext("Profil et en-tête")
  defp page_title(:year), do: gettext("Année scolaire et calendrier")
  defp page_title(:subjects), do: gettext("Matières")
  defp page_title(_), do: gettext("Paramètres")

  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-settings-page" class="mx-auto max-w-5xl space-y-8">
        <.page_header
          eyebrow={gettext("École")}
          title={gettext("Paramètres")}
          subtitle={gettext("Ce qu'on règle une fois par an. Le travail du jour est dans le menu.")}
        />

        <.hub_group
          :if={@can_edit_profile? or @can_rename_school? or @years != [] or @can_manage_periods?}
          title={gettext("L'établissement")}
        >
          <.hub_card
            :if={@can_edit_profile? or @can_rename_school?}
            id="hub-profile"
            navigate={~p"/school/settings/profile"}
            icon="hero-building-library"
            title={gettext("Profil et en-tête officiel")}
            text={gettext("Nom, type, coordonnées, logo, en-tête des documents imprimés.")}
            status={profile_status(@profile)}
          />
          <.hub_card
            id="hub-year"
            navigate={~p"/school/settings/year"}
            icon="hero-calendar-days"
            title={gettext("Année scolaire et calendrier")}
            text={gettext("Trimestres, séquences, limites de saisie, conseils de classe.")}
            status={year_status(@active_year, @active_sequences)}
          />
          <.hub_card
            :if={@can_manage_subjects?}
            id="holidays-link"
            navigate={~p"/school/settings/holidays"}
            icon="hero-sun"
            title={gettext("Congés & jours fériés")}
            text={gettext("Les jours sans cours, exclus des appels.")}
          />
          <.hub_card
            :if={@can_manage_periods?}
            id="periods-link"
            navigate={~p"/school/periods"}
            icon="hero-clock"
            title={gettext("Horaires des cours")}
            text={gettext("Jours de classe, créneaux, récréations.")}
          />
        </.hub_group>

        <.hub_group :if={@can_manage_subjects?} title={gettext("Notes et bulletins")}>
          <.hub_card
            id="hub-subjects"
            navigate={~p"/school/settings/subjects"}
            icon="hero-book-open"
            title={gettext("Matières")}
            text={gettext("Le catalogue des matières et leur groupe sur le bulletin.")}
            status={
              {:ok,
               ngettext(
                 "1 matière active",
                 "%{count} matières actives",
                 Enum.count(@subjects, & &1.active?)
               )}
            }
          />
          <.hub_card
            id="coefficients-link"
            navigate={~p"/school/settings/coefficients"}
            icon="hero-table-cells"
            title={gettext("Coefficients")}
            text={gettext("La grille des coefficients par niveau et par série.")}
          />
          <.hub_card
            id="evaluations-link"
            navigate={~p"/school/settings/evaluations"}
            icon="hero-calculator"
            title={gettext("Évaluations & moyennes")}
            text={gettext("Types d'évaluation, barème, calcul des moyennes.")}
          />
          <.hub_card
            id="appreciations-link"
            navigate={~p"/school/settings/appreciations"}
            icon="hero-academic-cap"
            title={gettext("Appréciations & distinctions")}
            text={gettext("Mentions, tableau d'honneur, avertissements.")}
          />
          <.hub_card
            id="passage-link"
            navigate={~p"/school/settings/passage"}
            icon="hero-arrow-trending-up"
            title={gettext("Passage & redoublement")}
            text={gettext("Seuils de passage par niveau.")}
          />
          <.hub_card
            id="bulletin-template-link"
            navigate={~p"/school/settings/bulletin"}
            icon="hero-document-duplicate"
            title={gettext("Modèle de bulletin")}
            text={gettext("Mise en page et blocs affichés.")}
          />
        </.hub_group>

        <.hub_group :if={@can_manage_subjects?} title={gettext("Organisation et accès")}>
          <.hub_card
            id="assignments-link"
            navigate={~p"/school/settings/assignments"}
            icon="hero-squares-2x2"
            title={gettext("Affectations")}
            text={gettext("Qui enseigne quoi, dans quelle classe.")}
          />
          <.hub_card
            id="school-life-link"
            navigate={~p"/school/settings/school-life"}
            icon="hero-scale"
            title={gettext("Assiduité & discipline")}
            text={gettext("Seuils d'absence et barème de conduite.")}
          />
          <.hub_card
            id="roles-link"
            navigate={~p"/school/settings/roles"}
            icon="hero-key"
            title={gettext("Rôles et droits")}
            text={gettext("Ce que chaque rôle peut voir et faire.")}
          />
        </.hub_group>
      </section>
    </Layouts.app>
    """
  end

  def render(%{live_action: :profile} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-settings-page" class="mx-auto max-w-3xl space-y-6">
        <.settings_back title={gettext("Profil et en-tête officiel")} />

        <.form
          :if={@can_rename_school? or (@can_edit_profile? and @profile_form)}
          for={@profile_form || to_form(%{}, as: :profile)}
          id="school-profile-form"
          phx-change="validate_profile"
          phx-submit="save_profile"
          phx-hook="DirtyForm"
          class="space-y-5"
        >
          <.settings_section title={gettext("Identité")}>
            <.settings_row
              :if={@can_rename_school?}
              label={gettext("Nom de l'école")}
              for="school_name"
            >
              <.input field={@name_form[:name]} type="text" />
            </.settings_row>
            <%= if @can_edit_profile? and @profile_form do %>
              <.settings_row
                label={gettext("Nom court")}
                for="profile_short_name"
                help={gettext("Affiché quand la place manque (en-têtes, téléphone).")}
              >
                <.input field={@profile_form[:short_name]} />
              </.settings_row>
              <.settings_row label={gettext("Type d'établissement")} for="profile_school_type">
                <.input
                  type="select"
                  field={@profile_form[:school_type]}
                  options={for t <- SchoolType.values(), do: {SchoolType.label(t), t}}
                  prompt={gettext("Sélectionner un type")}
                />
              </.settings_row>
              <.settings_row label={gettext("Sous-système")} for="profile_subsystem">
                <.input
                  type="select"
                  field={@profile_form[:subsystem]}
                  options={for s <- SchoolSubsystem.values(), do: {SchoolSubsystem.label(s), s}}
                  prompt={gettext("Sélectionner un sous-système")}
                />
              </.settings_row>
              <.settings_row label={gettext("Secteur")} for="profile_sector">
                <.input
                  type="select"
                  field={@profile_form[:sector]}
                  options={for s <- SchoolSector.values(), do: {SchoolSector.label(s), s}}
                  prompt={gettext("Sélectionner un secteur")}
                />
              </.settings_row>
            <% end %>
          </.settings_section>

          <%= if @can_edit_profile? and @profile_form do %>
            <.settings_section title={gettext("Coordonnées")}>
              <.settings_row label={gettext("Région")} for="profile_region">
                <.input
                  type="select"
                  field={@profile_form[:region]}
                  options={for r <- CameroonRegion.values(), do: {CameroonRegion.label(r), r}}
                  prompt={gettext("Sélectionner une région")}
                />
              </.settings_row>
              <.settings_row label={gettext("Département")} for="profile_department">
                <.input field={@profile_form[:department]} />
              </.settings_row>
              <.settings_row label={gettext("Ville")} for="profile_town">
                <.input field={@profile_form[:town]} />
              </.settings_row>
              <.settings_row label={gettext("Adresse")} for="profile_address">
                <.input field={@profile_form[:address]} />
              </.settings_row>
              <.settings_row label={gettext("Téléphone")} for="profile_phone">
                <.input field={@profile_form[:phone]} type="tel" />
              </.settings_row>
              <.settings_row label={gettext("Email")} for="profile_email">
                <.input field={@profile_form[:email]} type="email" />
              </.settings_row>
            </.settings_section>

            <.settings_section title={gettext("Direction et documents")}>
              <.settings_row label={gettext("Nom du chef d'établissement")} for="profile_head_name">
                <.input field={@profile_form[:head_name]} />
              </.settings_row>
              <.settings_row label={gettext("Devise")} for="profile_motto">
                <.input field={@profile_form[:motto]} />
              </.settings_row>
              <.settings_row
                label={gettext("Numéro d'autorisation")}
                for="profile_registration_number"
              >
                <.input field={@profile_form[:registration_number]} />
              </.settings_row>
            </.settings_section>

            <.settings_section title={gettext("Classes")}>
              <.settings_row
                label={gettext("Effectif maximum par classe")}
                for="profile_max_class_size"
                help={gettext("Au-delà, la classe est signalée « pleine ».")}
              >
                <.input field={@profile_form[:max_class_size]} type="number" />
              </.settings_row>
              <.settings_row label={gettext("Nommage des classes")} for="profile_class_suffix">
                <.input
                  field={@profile_form[:class_suffix]}
                  type="select"
                  options={
                    Enum.map(
                      TeacherAssistant.Academics.ClassSuffix.values(),
                      &{TeacherAssistant.Academics.ClassSuffix.label(&1), &1}
                    )
                  }
                />
              </.settings_row>
            </.settings_section>
          <% end %>

          <.save_bar />
        </.form>

        <.settings_section
          :if={@can_edit_profile? and @profile}
          id="school-logo"
          title={gettext("Logo et en-tête officiel")}
          subtitle={gettext("Le logo apparaît sur les bulletins, les cartes et les impressions.")}
        >
          <.form
            for={%{}}
            id="school-logo-form"
            phx-submit="save_logo"
            phx-change="validate_logo"
            multipart
            class="ta-setting"
          >
            <div class="flex items-center gap-4">
              <img
                :if={@profile.logo_path}
                src={~p"/school/logo"}
                alt={gettext("Logo de l'école")}
                class="size-16 rounded-lg border border-base-300 object-cover"
              />
              <span
                :if={!@profile.logo_path}
                class="grid size-16 place-items-center rounded-lg border border-dashed border-base-300 text-base-content/50"
              >
                <.icon name="hero-photo" class="size-6" />
              </span>
              <span class="text-sm text-base-content/70">
                {if @profile.logo_path,
                  do: gettext("Logo actuel"),
                  else: gettext("Pas encore de logo")}
              </span>
            </div>
            <div class="ta-setting__control flex flex-wrap items-center gap-2">
              <.file_picker upload={@uploads.logo} />
              <button :if={@uploads.logo.entries != []} type="submit" class="btn btn-primary">
                {gettext("Enregistrer le logo")}
              </button>
            </div>
          </.form>
          <.list_row
            id="official-header-link"
            navigate={~p"/school/settings/header"}
            title={gettext("En-tête officiel, signature et cachet")}
            meta={gettext("République, ministère, délégation, signature du chef d'établissement.")}
          >
            <:leading>
              <span class="grid size-10 place-items-center rounded-lg bg-base-200">
                <.icon name="hero-document-text" class="size-5" />
              </span>
            </:leading>
          </.list_row>
        </.settings_section>
      </section>
    </Layouts.app>
    """
  end

  def render(%{live_action: :year} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-settings-page" class="mx-auto max-w-3xl space-y-6">
        <.settings_back title={gettext("Année scolaire et calendrier")} />

        <.settings_section :if={@can_manage_calendar?} id="annee" title={gettext("Années scolaires")}>
          <:actions>
            <.link
              :if={@active_year && @active_year.status == :open}
              id="new-year-link"
              navigate={~p"/school/settings/new-year"}
              class="btn btn-sm btn-primary"
            >
              {gettext("Préparer l'année suivante")}
            </.link>
          </:actions>
          <div id="years-table">
            <.list_row
              :for={year <- @years}
              id={"year-row-#{year.id}"}
              navigate={year.status == :closed && ~p"/school/years/#{year.id}"}
              title={year.name}
              meta={"#{Dates.day_month(year.start_date)} #{year.start_date.year} → #{Dates.day_month(year.end_date)} #{year.end_date.year}"}
            >
              <:trailing>
                <span :if={year.status == :closed} class="badge badge-ghost">{gettext("Clôturée")}</span>
                <span :if={year.status == :open and year.active} class="badge badge-primary">
                  {gettext("Active")}
                </span>
                <span :if={year.status == :open and !year.active} class="badge badge-ghost">
                  {gettext("Inactive")}
                </span>
              </:trailing>
            </.list_row>
          </div>
          <div :if={@years == []} class="px-5 pb-5">
            <.empty_state icon="hero-calendar" title={gettext("No academic years yet")} />
          </div>
        </.settings_section>

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

        <%!-- Every member sees the calendar; only calendar managers can edit it. --%>
        <section
          :if={@active_year && @active_sequences != []}
          id={"year-calendar-#{@active_year.id}"}
          class="space-y-4"
        >
          <div>
            <h2 class="text-lg font-semibold">
              {gettext("Trimestres et séquences")} · {@active_year.name}
            </h2>
            <p class="mt-1 text-sm text-base-content/70">
              {gettext(
                "Sans date limite, la saisie des notes ferme %{days} jours après la fin de la séquence.",
                days: TeacherAssistant.Academics.Reference.entry_grace_days()
              )}
            </p>
          </div>

          <.form
            for={to_form(%{}, as: :calendar)}
            id="calendar-form"
            phx-submit="save_calendar"
            phx-hook="DirtyForm"
            class="space-y-4"
          >
            <.settings_section
              :for={{term, seqs} <- terms(@active_sequences)}
              id={"term-#{term.id}"}
              title={gettext("Trimestre %{n}", n: term.position)}
            >
              <div :for={seq <- seqs} id={"sequence-#{seq.id}"} class="ta-setting !block space-y-2">
                <p class="text-sm font-semibold">{gettext("Séquence %{n}", n: seq.number)}</p>
                <div class="grid gap-3 sm:grid-cols-3">
                  <div :for={field <- [:start_date, :end_date, :entry_deadline]}>
                    <.input
                      type="date"
                      label={calendar_label(field)}
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
                    <p
                      :if={field == :entry_deadline and is_nil(seq.entry_deadline)}
                      class="mt-1 text-xs text-base-content/60"
                    >
                      {gettext("Par défaut : %{date}", date: Dates.short(seq.grade_entry_deadline))}
                    </p>
                  </div>
                </div>
              </div>
              <.settings_row
                label={gettext("Conseil de classe")}
                for={"council-#{term.id}"}
                help={gettext("Après la fin du trimestre.")}
              >
                <.input
                  id={"council-#{term.id}"}
                  type="date"
                  name={"calendar[terms][#{term.id}][class_council_date]"}
                  value={
                    calendar_value(
                      @calendar_params,
                      "terms",
                      term.id,
                      :class_council_date,
                      term.class_council_date
                    )
                  }
                  disabled={!@can_manage_calendar?}
                  errors={calendar_errors(@calendar_errors, term.id, :class_council_date)}
                />
              </.settings_row>
            </.settings_section>

            <.save_bar :if={@can_manage_calendar?} label={gettext("Enregistrer le calendrier")} />
          </.form>
        </section>
      </section>
    </Layouts.app>
    """
  end

  def render(%{live_action: :subjects} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-settings-page" class="mx-auto max-w-3xl space-y-6">
        <.settings_back title={gettext("Matières")} />

        <section :if={@can_manage_subjects?} id="matieres" class="space-y-5">
          <.settings_section
            title={gettext("Ajouter une matière")}
            subtitle={gettext("Le coefficient se règle ensuite par niveau dans Coefficients.")}
          >
            <.form
              for={@subject_form}
              id="subject-form"
              phx-change="validate_subject"
              phx-submit="create_subject"
              class="flex flex-wrap items-end gap-3 px-4 pb-4 sm:px-5"
            >
              <div class="min-w-48 flex-1">
                <.input field={@subject_form[:name]} label={gettext("Nom de la matière")} />
              </div>
              <div class="min-w-48">
                <.input
                  field={@subject_form[:bulletin_group]}
                  type="select"
                  label={gettext("Groupe du bulletin")}
                  options={bulletin_group_options()}
                />
              </div>
              <button type="submit" class="btn btn-primary">{gettext("Ajouter")}</button>
            </.form>
          </.settings_section>

          <.settings_section
            title={gettext("Catalogue")}
            subtitle={gettext("Touchez une matière pour la modifier.")}
          >
            <div id="subjects-table">
              <.list_row
                :for={s <- @subjects}
                id={"subject-row-#{s.id}"}
                phx-click="edit_subject"
                phx-value-id={s.id}
                title={s.name}
                meta={"#{BulletinGroup.label(s.bulletin_group)} · " <> gettext("coef. %{c}", c: Numbers.decimal(s.default_coefficient, trim: true))}
                selected={@editing_subject && @editing_subject.id == s.id}
              >
                <:trailing>
                  <span :if={!s.active?} class="badge badge-ghost">{gettext("Inactive")}</span>
                </:trailing>
              </.list_row>
            </div>
            <div :if={@subjects == []} class="px-5 pb-5">
              <.empty_state icon="hero-book-open" title={gettext("Aucune matière pour l'instant")} />
            </div>
          </.settings_section>
        </section>

        <.drawer
          :if={@editing_subject}
          id="subject-drawer"
          eyebrow={gettext("Matière")}
          title={@editing_subject.name}
          on_close={JS.push("close_subject")}
        >
          <.form
            for={
              AshPhoenix.Form.for_update(@editing_subject, :update, as: "subject_edit", scope: @scope)
              |> to_form()
            }
            id={"subject-edit-form-#{@editing_subject.id}"}
            phx-submit="update_subject"
            class="space-y-1"
          >
            <input type="hidden" name="subject_id" value={@editing_subject.id} />
            <.input name="subject_edit[name]" value={@editing_subject.name} label={gettext("Nom")} />
            <.input
              name="subject_edit[default_coefficient]"
              value={@editing_subject.default_coefficient}
              label={gettext("Coefficient par défaut")}
              inputmode="decimal"
            />
            <.input
              name="subject_edit[bulletin_group]"
              type="select"
              value={to_string(@editing_subject.bulletin_group)}
              options={bulletin_group_options()}
              label={gettext("Groupe du bulletin")}
            />
          </.form>
          <div class="space-y-2 border-t border-base-300 pt-4">
            <p class="text-sm text-base-content/70">
              {if @editing_subject.active?,
                do: gettext("Une matière désactivée n'est plus proposée aux classes."),
                else: gettext("Cette matière est désactivée.")}
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                id={"subject-toggle-active-#{@editing_subject.id}"}
                class="btn btn-ghost"
                phx-click="toggle_subject_active"
                phx-value-id={@editing_subject.id}
              >
                {if @editing_subject.active?, do: gettext("Désactiver"), else: gettext("Réactiver")}
              </button>
              <button
                type="button"
                id={"subject-delete-#{@editing_subject.id}"}
                phx-click="delete_subject"
                phx-value-id={@editing_subject.id}
                data-confirm={gettext("Supprimer cette matière ?")}
                class="btn btn-ghost text-error"
              >
                {gettext("Supprimer")}<span class="sr-only">{@editing_subject.name}</span>
              </button>
            </div>
          </div>
          <:footer>
            <button type="button" class="btn btn-ghost" phx-click="close_subject">
              {gettext("Fermer")}
            </button>
            <button
              type="submit"
              form={"subject-edit-form-#{@editing_subject.id}"}
              class="btn btn-primary"
            >
              {gettext("Enregistrer")}
            </button>
          </:footer>
        </.drawer>
      </section>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true

  defp settings_back(assigns) do
    ~H"""
    <header class="space-y-1">
      <.link
        navigate={~p"/school/settings"}
        class="link link-hover inline-flex items-center gap-1 text-sm font-semibold text-info"
      >
        <.icon name="hero-chevron-left" class="size-4" />{gettext("Paramètres")}
      </.link>
      <h1 class="text-2xl font-semibold leading-tight sm:text-[2rem]">{@title}</h1>
    </header>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp hub_group(assigns) do
    ~H"""
    <section class="space-y-3">
      <h2 class="text-base font-semibold">{@title}</h2>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :status, :any, default: nil, doc: "{:ok | :todo, text} or nil"

  defp hub_card(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="ta-section group flex min-h-28 flex-col gap-2 p-4 transition-colors hover:border-base-content/30"
    >
      <span class="flex items-center gap-2.5 font-semibold">
        <.icon name={@icon} class="size-5 text-primary" />
        <span class="flex-1">{@title}</span>
        <.icon
          name="hero-chevron-right"
          class="size-4 text-base-content/40 transition-transform group-hover:translate-x-0.5"
        />
      </span>
      <span class="flex-1 text-sm text-base-content/70">{@text}</span>
      <span
        :if={@status}
        class={[
          "inline-flex items-center gap-1.5 text-xs font-semibold",
          if(elem(@status, 0) == :ok, do: "text-success", else: "text-error")
        ]}
      >
        <span class="size-1.5 rounded-full bg-current"></span>{elem(@status, 1)}
      </span>
    </.link>
    """
  end

  @profile_fields ~w(short_name school_type region town phone head_name)a

  defp profile_status(nil), do: nil

  defp profile_status(profile) do
    case Enum.count(@profile_fields, &(Map.get(profile, &1) in [nil, ""])) do
      0 -> {:ok, gettext("Complet")}
      n -> {:todo, ngettext("1 information manquante", "%{count} informations manquantes", n)}
    end
  end

  defp year_status(nil, _), do: {:todo, gettext("Aucune année active")}
  defp year_status(year, []), do: {:todo, gettext("%{name} · pas de calendrier", name: year.name)}

  defp year_status(year, seqs),
    do:
      {:ok,
       ngettext("%{name} · 1 séquence", "%{name} · %{count} séquences", length(seqs),
         name: year.name
       )}

  defp terms(sequences) do
    sequences
    |> Enum.group_by(& &1.term_id)
    |> Enum.map(fn {_id, [first | _] = seqs} -> {first.term, Enum.sort_by(seqs, & &1.number)} end)
    |> Enum.sort_by(fn {term, _} -> term.position end)
  end

  defp calendar_label(:start_date), do: gettext("Début")
  defp calendar_label(:end_date), do: gettext("Fin")
  defp calendar_label(:entry_deadline), do: gettext("Limite de saisie")

  def handle_event("edit_subject", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, :editing_subject, Enum.find(socket.assigns.subjects, &(&1.id == id)))}
  end

  def handle_event("close_subject", _params, socket),
    do: {:noreply, assign(socket, :editing_subject, nil)}

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
          {:noreply,
           socket
           |> assign(:subjects, Curriculum.list_subjects(scope))
           |> assign(:editing_subject, nil)}
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
           |> assign(:editing_subject, nil)
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
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:subjects, Curriculum.list_subjects(scope))
           |> assign(:editing_subject, updated)}

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

  # One form for the school's name (Workspace) and its profile (SchoolProfile):
  # each part is validated and saved with its own resource and policy.
  def handle_event("validate_profile", params, socket) do
    socket =
      socket
      |> validate_part(:name_form, params["school"], socket.assigns.can_rename_school?)
      |> validate_part(:profile_form, params["profile"], socket.assigns.profile_form != nil)

    {:noreply, socket}
  end

  def handle_event("save_profile", params, socket) do
    with {:ok, socket} <- save_name(socket, params["school"]),
         {:ok, socket} <- save_profile(socket, params["profile"]) do
      {:noreply,
       socket |> load_profile() |> put_flash(:info, gettext("Profil de l'école mis à jour."))}
    else
      {:forbidden, socket} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, gettext("Impossible de mettre à jour le profil."))}
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

  defp validate_part(socket, _key, nil, _allowed?), do: socket
  defp validate_part(socket, _key, _params, false), do: socket

  defp validate_part(socket, key, params, true),
    do: assign(socket, key, AshPhoenix.Form.validate(socket.assigns[key], params))

  defp save_name(socket, params) when is_nil(params) or not socket.assigns.can_rename_school?,
    do: {:ok, socket}

  defp save_name(socket, params) do
    scope = socket.assigns.scope

    case AshPhoenix.Form.submit(socket.assigns.name_form, params: params) do
      {:ok, school} ->
        new_scope = %{scope | current_workspace: school}

        {:ok,
         socket
         |> assign(:scope, new_scope)
         |> assign(:current_scope, new_scope)
         |> assign(:name_form, name_form(new_scope))}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:forbidden, socket},
          else: {:error, assign(socket, :name_form, form)}
    end
  end

  defp save_profile(socket, params) when is_nil(params) or is_nil(socket.assigns.profile_form),
    do: {:ok, socket}

  defp save_profile(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.profile_form, params: params) do
      {:ok, _profile} ->
        {:ok, socket}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:forbidden, socket},
          else: {:error, assign(socket, :profile_form, form)}
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
