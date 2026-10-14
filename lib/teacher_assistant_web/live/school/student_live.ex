defmodule TeacherAssistantWeb.School.StudentLive do
  @moduledoc """
  Student profile (spec KLM1, M3; Élèves redesign 2026-10-08): identity,
  parents and guardians with their other children, class history with passage
  decisions and published results, this year's attendance and discipline.
  Editing for admins and the SG; reading for the student's form masters and
  teachers.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.StudentPhotoComponents

  alias TeacherAssistant.{Attendance, Councils, Discipline, Enrollment, Organization, ReportCards}

  alias TeacherAssistant.Academics.{
    ContactLanguage,
    Guardian,
    GuardianRelationship,
    PassageDecision,
    Sex
  }

  alias TeacherAssistantWeb.Authz
  alias TeacherAssistantWeb.School.ClassShell

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, student} <- Enrollment.fetch_owned_student(scope, id),
         access when access != :none <- Enrollment.student_access(scope, student) do
      {:ok,
       socket
       |> assign(
         student: student,
         access: access,
         editing: false,
         adding_guardian: false,
         match: [],
         match_children: %{},
         guardian_edit: nil,
         sheet: false,
         confirm_remove?: false
       )
       |> assign_guardian_form(%{})
       |> allow_photo_upload_for(access)
       |> load()}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Élève introuvable."))
         |> push_navigate(to: ~p"/school/students")}

      :none ->
        {:ok, socket |> Authz.put_not_allowed() |> push_navigate(to: ~p"/school")}
    end
  end

  defp allow_photo_upload_for(socket, :manage), do: allow_photo_upload(socket, &handle_progress/3)
  defp allow_photo_upload_for(socket, _access), do: socket

  # Spec 2026-10-12 §8: the photo sheet on the student page.
  defp handle_progress(:photo, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_progress(:photo, entry, socket) do
    %{student: student} = socket.assigns

    if entry_student_id(entry) == student.id do
      case store_entry(socket, student, entry) do
        {:ok, updated} ->
          {:noreply, socket |> assign(student: updated, sheet: false) |> photo_stored(student.id)}

        {:error, message} ->
          {:noreply, photo_failed(socket, student.id, message)}
      end
    else
      discard_entry(socket, entry)

      {:noreply,
       photo_failed(
         socket,
         entry_student_id(entry),
         gettext("Cette photo ne correspond pas à cet élève.")
       )}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    student = socket.assigns.student
    year = scope.current_academic_year
    history = Enrollment.student_history(scope, student)
    current = year && Enum.find(history, &(&1.academic_year_id == year.id))
    links = Enrollment.list_guardian_links(scope, student)

    assign(socket,
      links: links,
      children: Enrollment.guardian_children(scope, Enum.map(links, & &1.guardian_id)),
      history: Enum.sort_by(history, & &1.academic_year.start_date, {:desc, Date}),
      results: Map.new(history, &{&1.id, ReportCards.latest_published_result(scope, &1)}),
      decisions: Councils.annual_decisions(scope, student.id),
      current: current,
      register?: current && ClassShell.allowed?(scope, current.class_group, :register),
      this_year: current && this_year(scope, current, year)
    )
  end

  defp this_year(scope, enrollment, year) do
    %{
      enrollment: enrollment,
      attendance: Attendance.student_conduct(scope, enrollment, {:annual, year}),
      discipline: Discipline.discipline_summary(scope, enrollment, {:annual, year}),
      conduct:
        scope
        |> Organization.list_sequences(year)
        |> Enum.map(&{&1, Discipline.note_de_conduite(scope, enrollment, {:sequence, &1})})
    }
  end

  defp assign_guardian_form(socket, params) do
    assign(socket, guardian_form: to_form(params, as: "guardian"))
  end

  # --- Identity ---

  def handle_event("edit_identity", _params, socket) when socket.assigns.access == :manage do
    form =
      AshPhoenix.Form.for_update(socket.assigns.student, :update,
        as: "student",
        scope: socket.assigns.current_scope
      )

    {:noreply, assign(socket, editing: true, identity_form: to_form(form))}
  end

  def handle_event("cancel_identity", _params, socket),
    do: {:noreply, assign(socket, editing: false)}

  def handle_event("save_identity", %{"student" => params}, socket)
      when socket.assigns.access == :manage do
    case AshPhoenix.Form.submit(socket.assigns.identity_form.source, params: params) do
      {:ok, student} ->
        {:noreply,
         socket
         |> assign(student: student, editing: false)
         |> put_flash(:info, gettext("Identité enregistrée."))}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:noreply, Authz.put_not_allowed(socket)},
          else: {:noreply, assign(socket, identity_form: to_form(form))}
    end
  end

  # --- Guardians ---

  def handle_event("toggle_add_guardian", _params, socket)
      when socket.assigns.access == :manage do
    {:noreply,
     socket
     |> assign(adding_guardian: not socket.assigns.adding_guardian, match: [])
     |> assign_guardian_form(%{})}
  end

  def handle_event("guardian_change", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage do
    linked = MapSet.new(socket.assigns.links, & &1.guardian_id)

    scope = socket.assigns.current_scope

    match =
      scope
      |> Enrollment.find_guardians_by_phone(params["phone"] || "")
      |> Enum.reject(&MapSet.member?(linked, &1.id))

    {:noreply,
     socket
     |> assign(
       match: match,
       match_children: Enrollment.guardian_children(scope, Enum.map(match, & &1.id))
     )
     |> assign_guardian_form(params)}
  end

  def handle_event("add_guardian", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage do
    attrs = Map.take(params, ~w(full_name relationship phone phone_2 email language))

    case Enrollment.add_guardian(socket.assigns.current_scope, socket.assigns.student, attrs) do
      {:ok, _guardian} ->
        {:noreply,
         socket
         |> assign(match: [], adding_guardian: false)
         |> assign_guardian_form(%{})
         |> load()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, error} ->
        {:noreply,
         socket |> assign_guardian_form(params) |> put_flash(:error, error_message(error))}
    end
  end

  def handle_event("link_guardian", %{"id" => id}, socket)
      when socket.assigns.access == :manage do
    with %Guardian{} = guardian <- Enum.find(socket.assigns.match, &(&1.id == id)),
         {:ok, _} <-
           Enrollment.link_guardian(
             socket.assigns.current_scope,
             socket.assigns.student,
             guardian
           ) do
      {:noreply,
       socket |> assign(match: [], adding_guardian: false) |> assign_guardian_form(%{}) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Impossible de lier ce parent."))}
    end
  end

  def handle_event("edit_guardian", %{"id" => id}, socket)
      when socket.assigns.access == :manage do
    case Enum.find(socket.assigns.links, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      link ->
        form =
          AshPhoenix.Form.for_update(link.guardian, :update,
            as: "guardian",
            id: "guardian_edit",
            scope: socket.assigns.current_scope
          )

        # Own id prefix: the add form beside it uses the same field names.
        {:noreply, assign(socket, guardian_edit: %{link_id: id, form: to_form(form)})}
    end
  end

  def handle_event("cancel_guardian", _params, socket),
    do: {:noreply, assign(socket, guardian_edit: nil)}

  def handle_event("save_guardian", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage and socket.assigns.guardian_edit != nil do
    case AshPhoenix.Form.submit(socket.assigns.guardian_edit.form.source, params: params) do
      {:ok, _guardian} ->
        {:noreply,
         socket
         |> assign(guardian_edit: nil)
         |> put_flash(:info, gettext("Parent mis à jour."))
         |> load()}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:noreply, Authz.put_not_allowed(socket)},
          else:
            {:noreply,
             assign(socket,
               guardian_edit: %{socket.assigns.guardian_edit | form: to_form(form)}
             )}
    end
  end

  def handle_event("make_primary", %{"id" => id}, socket) when socket.assigns.access == :manage do
    run_on_link(socket, id, &Enrollment.make_primary_guardian/2)
  end

  def handle_event("unlink", %{"id" => id}, socket) when socket.assigns.access == :manage do
    run_on_link(socket, id, &Enrollment.unlink_guardian/2)
  end

  # Any write event from a read-only visitor.
  def handle_event("validate_photo", _params, socket),
    do: {:noreply, drop_refused_entries(socket)}

  def handle_event("photo_unreadable", _params, socket),
    do: {:noreply, put_flash(socket, :error, unreadable_message())}

  def handle_event("open_sheet", _params, socket) when socket.assigns.access == :manage,
    do: {:noreply, assign(socket, sheet: true, confirm_remove?: false)}

  def handle_event("close_sheet", _params, socket),
    do: {:noreply, assign(socket, sheet: false, confirm_remove?: false)}

  def handle_event("ask_remove", _params, socket) when socket.assigns.access == :manage,
    do: {:noreply, assign(socket, confirm_remove?: true)}

  def handle_event("remove_photo", _params, socket) when socket.assigns.access == :manage do
    case remove_photo(socket, socket.assigns.student) do
      {:ok, student} ->
        {:noreply, assign(socket, student: student, sheet: false, confirm_remove?: false)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, Authz.put_not_allowed(socket)}

  defp run_on_link(socket, id, fun) do
    with %{} = link <- Enum.find(socket.assigns.links, &(&1.id == id)),
         result when result == :ok or elem(result, 0) == :ok <-
           fun.(socket.assigns.current_scope, link) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action impossible."))}
    end
  end

  defp error_message(%Ash.Error.Invalid{errors: errors}),
    do: Enum.map_join(errors, " ", &Exception.message/1)

  defp error_message(_error), do: gettext("Impossible d'enregistrer le parent.")

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  # Full years at today's date.
  defp age(nil), do: nil

  defp age(%Date{} = birth) do
    today = Date.utc_today()
    years = today.year - birth.year
    if {today.month, today.day} < {birth.month, birth.day}, do: years - 1, else: years
  end

  defp identity_line(student) do
    case age(student.birth_date) do
      nil -> Sex.label(student.sex)
      years -> "#{Sex.label(student.sex)} · #{ngettext("%{count} an", "%{count} ans", years)}"
    end
  end

  # « aussi parent de Ebogo Ivan (3e A) », without the student shown.
  defp other_children(children, guardian_id, student_id) do
    children
    |> Map.get(guardian_id, [])
    |> Enum.reject(&(&1.student.id == student_id))
    |> Enum.map_join(", ", &child_text/1)
  end

  defp child_text(%{student: s, class_label: nil}), do: s.full_name
  defp child_text(%{student: s, class_label: label}), do: "#{s.full_name} (#{label})"

  # « mère de 2 élèves (4e A, 2nde C) »
  defp match_text(guardian, children) do
    labels =
      children
      |> Map.get(guardian.id, [])
      |> Enum.map(& &1.class_label)
      |> Enum.reject(&is_nil/1)

    text =
      ngettext(
        "%{relationship} de %{count} élève",
        "%{relationship} de %{count} élèves",
        guardian.student_count,
        relationship: GuardianRelationship.label(guardian.relationship) |> String.downcase()
      )

    if labels == [], do: text, else: "#{text} (#{Enum.join(labels, ", ")})"
  end

  defp messages_in(:en), do: gettext("Messages en anglais")
  defp messages_in(_fr), do: gettext("Messages en français")

  defp result_line(nil), do: nil

  defp result_line(%{period: period, average: average, rank: rank, effectif: effectif}) do
    label =
      case period do
        :annual -> gettext("Année")
        {:trimester, term} -> gettext("Trim. %{n}", n: term.position)
      end

    gettext("%{period} : %{average} · %{rank} / %{effectif}",
      period: label,
      average: if(average, do: average |> Decimal.round(2) |> Decimal.to_string(), else: "—"),
      rank: rank_text(rank),
      effectif: effectif
    )
  end

  defp rank_text(nil), do: "—"
  defp rank_text(1), do: gettext("1er")
  defp rank_text(n), do: gettext("%{n}e", n: n)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="student" class="flex flex-col gap-5">
        <.breadcrumb id="student-breadcrumb">
          <:crumb navigate={@access == :manage && ~p"/school/students"}>{gettext("Élèves")}</:crumb>
          <:crumb>{@student.full_name}</:crumb>
        </.breadcrumb>

        <header id="student-header" class="flex flex-wrap items-end justify-between gap-4">
          <div class="flex min-w-0 items-center gap-4">
            <button
              :if={@access == :manage}
              id="student-photo-button"
              type="button"
              phx-click="open_sheet"
              aria-label={gettext("Changer la photo")}
              class="group relative shrink-0 rounded-full transition hover:scale-105 focus-visible:outline-2 focus-visible:outline-primary"
            >
              <.student_avatar student={@student} class="size-14 text-lg" />
              <span class="absolute -bottom-0.5 -right-0.5 grid size-5 place-items-center rounded-full bg-base-content text-base-100 shadow">
                <.icon name="hero-camera-mini" class="size-3" />
              </span>
            </button>
            <.student_avatar
              :if={@access != :manage}
              student={@student}
              class="size-14 text-lg"
            />
            <div class="min-w-0 space-y-1.5">
              <h1 class="font-display text-3xl font-semibold leading-none sm:text-[2.2rem]">
                {@student.full_name}
              </h1>
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-base-content/80">
                <.link
                  :if={@current}
                  id="student-class"
                  navigate={~p"/school/classes/#{@current.class_group_id}"}
                  class="font-semibold text-base-content hover:text-primary"
                >
                  {@current.class_group.label}
                </.link>
                <span :if={!@current} id="student-class">{gettext("Pas inscrit cette année")}</span>
                <span :if={@student.matricule} class="ta-num">{@student.matricule}</span>
                <span id="student-sex-age">{identity_line(@student)}</span>
              </div>
            </div>
          </div>
          <div :if={@current} class="flex flex-wrap gap-2">
            <.link
              id="student-bulletin"
              navigate={
                ~p"/school/classes/#{@current.class_group_id}/students/#{@current.id}/bulletin"
              }
              class="btn btn-ghost btn-sm"
            >
              {gettext("Bulletin")}
            </.link>
            <a
              :if={@access == :manage}
              id="student-card"
              href={~p"/school/classes/#{@current.class_group_id}/cards/print?student=#{@student.id}"}
              target="_blank"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Carte scolaire")}
            </a>
            <.link
              :if={@register?}
              id="student-absences"
              navigate={~p"/school/classes/#{@current.class_group_id}/register"}
              class="btn btn-ghost btn-sm"
            >
              {gettext("Absences")}
            </.link>
          </div>
        </header>

        <div class="grid items-start gap-4 lg:grid-cols-2">
          <div class="flex flex-col gap-4">
            <article id="student-identity" class="ta-panel flex flex-col gap-3">
              <header class="flex items-center justify-between">
                <h2 class="font-display text-lg font-semibold">{gettext("Identité")}</h2>
                <button
                  :if={@access == :manage and not @editing}
                  id="edit-identity"
                  type="button"
                  phx-click="edit_identity"
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-pencil-square" class="size-4" /> {gettext("Modifier")}
                </button>
                <button
                  :if={@editing}
                  type="button"
                  phx-click="cancel_identity"
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Annuler")}
                </button>
              </header>

              <.form
                :if={@editing}
                for={@identity_form}
                id="identity-form"
                phx-submit="save_identity"
                class="grid gap-2 sm:grid-cols-2"
              >
                <div class="sm:col-span-2">
                  <.input field={@identity_form[:full_name]} label={gettext("Nom et prénoms")} />
                </div>
                <.input
                  field={@identity_form[:sex]}
                  type="select"
                  label={gettext("Sexe")}
                  options={Enum.map(Sex.values(), &{Sex.label(&1), &1})}
                />
                <.input field={@identity_form[:matricule]} label={gettext("Matricule")} />
                <.input
                  field={@identity_form[:birth_date]}
                  type="date"
                  label={gettext("Date de naissance")}
                />
                <.input field={@identity_form[:birth_place]} label={gettext("Lieu de naissance")} />
                <div class="sm:col-span-2">
                  <button class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
                </div>
              </.form>

              <dl :if={not @editing} class="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                <div class="col-span-2">
                  <dt class="ta-eyebrow">{gettext("Nom et prénoms")}</dt>
                  <dd class="mt-0.5">{@student.full_name}</dd>
                </div>
                <div>
                  <dt class="ta-eyebrow">{gettext("Sexe")}</dt>
                  <dd class="mt-0.5">{Sex.label(@student.sex)}</dd>
                </div>
                <div>
                  <dt class="ta-eyebrow">{gettext("Matricule")}</dt>
                  <dd class="ta-num mt-0.5">{@student.matricule || "—"}</dd>
                </div>
                <div>
                  <dt class="ta-eyebrow">{gettext("Date de naissance")}</dt>
                  <dd class="ta-num mt-0.5">{format_date(@student.birth_date)}</dd>
                </div>
                <div>
                  <dt class="ta-eyebrow">{gettext("Lieu de naissance")}</dt>
                  <dd class="mt-0.5">{@student.birth_place || "—"}</dd>
                </div>
              </dl>
            </article>

            <article id="student-guardians" class="ta-panel flex flex-col gap-3">
              <header class="flex items-center justify-between">
                <h2 class="font-display text-lg font-semibold">{gettext("Parents et tuteurs")}</h2>
                <button
                  :if={@access == :manage}
                  id="add-guardian"
                  type="button"
                  phx-click="toggle_add_guardian"
                  aria-expanded={to_string(@adding_guardian)}
                  class="btn btn-ghost btn-xs"
                >
                  {if @adding_guardian, do: gettext("Annuler"), else: gettext("+ Ajouter")}
                </button>
              </header>
              <p
                :if={@links != [] and not Enum.any?(@links, & &1.primary_contact)}
                class="text-sm text-warning"
              >
                {gettext("Aucun contact principal")}
              </p>
              <ul id="guardian-list" class="flex flex-col gap-2">
                <li
                  :for={l <- @links}
                  id={"guardian-#{l.id}"}
                  class="flex flex-wrap items-start justify-between gap-2 rounded-[0.6rem] border border-base-300 p-3"
                >
                  <span class="flex min-w-0 flex-col gap-0.5">
                    <span class="flex flex-wrap items-center gap-2">
                      <span class="font-semibold">{l.guardian.full_name}</span>
                      <span class="text-sm text-base-content/60">
                        {GuardianRelationship.label(l.guardian.relationship)}
                      </span>
                      <span
                        :if={l.primary_contact}
                        class="rounded-full bg-primary/15 px-2 py-0.5 text-[0.7rem] font-semibold text-primary"
                      >
                        {gettext("Contact principal")}
                      </span>
                    </span>
                    <span class="ta-num text-sm">
                      <a href={"tel:#{l.guardian.phone_key}"} class="link link-hover">{l.guardian.phone}</a>
                      <span :if={l.guardian.phone_2} class="text-base-content/70">
                        · {gettext("2nd : %{phone}", phone: l.guardian.phone_2)}
                      </span>
                    </span>
                    <span :if={l.guardian.email} class="text-xs">{l.guardian.email}</span>
                    <span id={"guardian-meta-#{l.id}"} class="text-xs text-base-content/60">
                      {messages_in(l.guardian.language)}
                      <%= case other_children(@children, l.guardian_id, @student.id) do %>
                        <% "" -> %>
                        <% others -> %>
                          · {gettext("aussi parent de %{children}", children: others)}
                      <% end %>
                    </span>
                  </span>
                  <span :if={@access == :manage} class="flex flex-wrap gap-1">
                    <button
                      id={"edit-guardian-#{l.id}"}
                      type="button"
                      phx-click="edit_guardian"
                      phx-value-id={l.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Modifier")}
                    </button>
                    <button
                      :if={not l.primary_contact}
                      id={"make-primary-#{l.id}"}
                      type="button"
                      phx-click="make_primary"
                      phx-value-id={l.id}
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Contact principal")}
                    </button>
                    <button
                      id={"unlink-#{l.id}"}
                      type="button"
                      phx-click="unlink"
                      phx-value-id={l.id}
                      data-confirm={gettext("Retirer ce parent de la fiche de l'élève ?")}
                      class="btn btn-ghost btn-xs text-error"
                    >
                      {gettext("Retirer")}
                    </button>
                  </span>
                </li>
              </ul>
              <.form
                :if={@guardian_edit}
                for={@guardian_edit.form}
                id="guardian-edit-form"
                phx-submit="save_guardian"
                class="grid gap-2 rounded-[0.6rem] border border-base-300 p-3 sm:grid-cols-2"
              >
                <.input field={@guardian_edit.form[:full_name]} label={gettext("Nom et prénoms")} />
                <.input
                  field={@guardian_edit.form[:relationship]}
                  type="select"
                  label={gettext("Lien")}
                  options={
                    Enum.map(GuardianRelationship.values(), &{GuardianRelationship.label(&1), &1})
                  }
                />
                <.input field={@guardian_edit.form[:phone]} label={gettext("Téléphone")} />
                <.input field={@guardian_edit.form[:phone_2]} label={gettext("Second téléphone")} />
                <.input field={@guardian_edit.form[:email]} type="email" label={gettext("E-mail")} />
                <.input
                  field={@guardian_edit.form[:language]}
                  type="select"
                  label={gettext("Langue des messages")}
                  options={Enum.map(ContactLanguage.values(), &{ContactLanguage.label(&1), &1})}
                />
                <div class="flex gap-2 sm:col-span-2">
                  <button class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
                  <button type="button" phx-click="cancel_guardian" class="btn btn-ghost btn-sm">
                    {gettext("Annuler")}
                  </button>
                </div>
              </.form>
              <p :if={@links == []} class="text-sm text-base-content/60">
                {gettext("Aucun parent enregistré.")}
              </p>

              <.form
                :if={@access == :manage and @adding_guardian}
                for={@guardian_form}
                id="guardian-form"
                phx-change="guardian_change"
                phx-submit="add_guardian"
                class="grid gap-2 rounded-[0.6rem] border border-primary/40 p-3 sm:grid-cols-2"
              >
                <div class="sm:col-span-2">
                  <.input
                    field={@guardian_form[:phone]}
                    type="tel"
                    inputmode="tel"
                    label={gettext("Téléphone — commencez par lui")}
                    placeholder="6XX XX XX XX"
                    phx-debounce="300"
                  />
                </div>
                <div
                  :if={@match != []}
                  id="guardian-match"
                  class="flex flex-col gap-2 rounded-[0.5rem] bg-primary/10 p-2 text-sm sm:col-span-2"
                >
                  <span :for={g <- @match} class="flex flex-wrap items-center justify-between gap-2">
                    <span>
                      {gettext("Déjà enregistré :")} <strong>{g.full_name}</strong>
                      — {match_text(g, @match_children)}
                    </span>
                    <button
                      type="button"
                      phx-click="link_guardian"
                      phx-value-id={g.id}
                      class="btn btn-primary btn-xs"
                    >
                      {gettext("Lier %{name}", name: g.full_name)}
                    </button>
                  </span>
                </div>
                <div class="sm:col-span-2">
                  <.input field={@guardian_form[:full_name]} label={gettext("Nom et prénoms")} />
                </div>
                <.input
                  field={@guardian_form[:relationship]}
                  type="select"
                  label={gettext("Lien")}
                  options={
                    Enum.map(GuardianRelationship.values(), &{GuardianRelationship.label(&1), &1})
                  }
                />
                <.input field={@guardian_form[:phone_2]} label={gettext("Second téléphone")} />
                <.input field={@guardian_form[:email]} type="email" label={gettext("E-mail")} />
                <.input
                  field={@guardian_form[:language]}
                  type="select"
                  label={gettext("Langue des messages")}
                  options={Enum.map(ContactLanguage.values(), &{ContactLanguage.label(&1), &1})}
                />
                <div class="flex gap-2 sm:col-span-2">
                  <button class="btn btn-primary btn-sm">{gettext("Ajouter le parent")}</button>
                  <button type="button" phx-click="toggle_add_guardian" class="btn btn-ghost btn-sm">
                    {gettext("Annuler")}
                  </button>
                </div>
              </.form>
            </article>
          </div>

          <div class="flex flex-col gap-4">
            <article :if={@this_year} id="student-this-year" class="ta-panel flex flex-col gap-3">
              <h2 class="font-display text-lg font-semibold">{gettext("Cette année")}</h2>
              <div class="grid grid-cols-2 gap-2">
                <div
                  :for={
                    {id, label, value, tone} <- [
                      {"unjustified", gettext("Absences injustifiées"),
                       "#{@this_year.attendance.unjustified_hours} h",
                       Decimal.gt?(@this_year.attendance.unjustified_hours, 0) && "text-warning"},
                      {"justified", gettext("Absences justifiées"),
                       "#{@this_year.attendance.justified_hours} h", nil},
                      {"retards", gettext("Retards"), "#{@this_year.attendance.retards}", nil},
                      {"consignes", gettext("Consignes"), "#{@this_year.discipline.consignes_count}",
                       nil}
                    ]
                  }
                  id={"this-year-#{id}"}
                  class="flex flex-col gap-0.5 rounded-[0.5rem] bg-base-200/60 px-3 py-2"
                >
                  <span class="text-xs text-base-content/70">{label}</span>
                  <span class={["ta-num text-xl font-semibold", tone]}>{value}</span>
                </div>
              </div>
              <ul :if={@this_year.discipline.sanctions != []} class="text-sm">
                <li :for={s <- @this_year.discipline.sanctions}>
                  <span class="ta-num">{format_date(s.date)}</span>
                  · {TeacherAssistant.Academics.SanctionType.label(s.type)}
                  <span :if={s.reason} class="text-base-content/60">— {s.reason}</span>
                </li>
              </ul>
              <p class="ta-num flex flex-wrap gap-x-3 border-t border-base-300 pt-2 text-sm">
                <span class="text-base-content/70">{gettext("Conduite")}</span>
                <span :for={{seq, value} <- @this_year.conduct}>
                  {gettext("Séq. %{n}", n: seq.number)} · <strong>{value || "—"}</strong>
                </span>
              </p>
            </article>

            <article id="student-history" class="ta-panel flex flex-col gap-2">
              <h2 class="font-display text-lg font-semibold">
                {gettext("Scolarité dans l'établissement")}
              </h2>
              <ul class="flex flex-col divide-y divide-base-300">
                <li
                  :for={e <- @history}
                  id={"history-#{e.id}"}
                  class="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 text-sm"
                >
                  <span class="ta-num text-base-content/70">{e.academic_year.name}</span>
                  <span class="font-semibold">{e.class_group.label}</span>
                  <span
                    :if={e.repeater}
                    class="rounded bg-warning/20 px-1.5 text-[0.7rem] font-semibold text-warning"
                  >
                    {gettext("Redoublant")}
                  </span>
                  <span :if={d = @decisions[e.class_group_id]}>{PassageDecision.label(d)}</span>
                  <span :if={line = result_line(@results[e.id])} class="ta-num text-base-content/80">
                    {line}
                  </span>
                  <.link
                    navigate={~p"/school/classes/#{e.class_group_id}/students/#{e.id}/bulletin"}
                    class="link link-primary ml-auto"
                  >
                    {gettext("Bulletin")}
                  </.link>
                </li>
              </ul>
            </article>
          </div>
        </div>
        <%= if @access == :manage do %>
          <.photo_sheet :if={@sheet} student={@student} confirm_remove?={@confirm_remove?} />
          <.photo_upload_form upload={@uploads.photo} />
          <.photo_studio id="photo-studio" student_id={@student.id} />
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
