defmodule TeacherAssistantWeb.School.StudentLive do
  @moduledoc """
  Student profile (spec KLM1, M3): identity, parents and guardians, class
  history with passage decisions and bulletins, this year's attendance and
  discipline. Editing for admins and the SG; reading for the student's
  form masters and teachers.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Councils, Discipline, Enrollment, Organization}

  alias TeacherAssistant.Academics.{
    ContactLanguage,
    Guardian,
    GuardianRelationship,
    PassageDecision,
    Sex
  }

  alias TeacherAssistantWeb.Authz

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, student} <- Enrollment.fetch_owned_student(scope, id),
         access when access != :none <- Enrollment.student_access(scope, student) do
      {:ok,
       socket
       |> assign(student: student, access: access, editing: false, match: [], guardian_edit: nil)
       |> assign_guardian_form(%{})
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

  defp load(socket) do
    scope = socket.assigns.current_scope
    student = socket.assigns.student
    year = scope.current_academic_year
    history = Enrollment.student_history(scope, student)
    current = year && Enum.find(history, &(&1.academic_year_id == year.id))

    assign(socket,
      links: Enrollment.list_guardian_links(scope, student),
      history: history,
      decisions: Councils.annual_decisions(scope, student.id),
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

  def handle_event("guardian_change", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage do
    linked = MapSet.new(socket.assigns.links, & &1.guardian_id)

    match =
      socket.assigns.current_scope
      |> Enrollment.find_guardians_by_phone(params["phone"] || "")
      |> Enum.reject(&MapSet.member?(linked, &1.id))

    {:noreply, socket |> assign(match: match) |> assign_guardian_form(params)}
  end

  def handle_event("add_guardian", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage do
    attrs = Map.take(params, ~w(full_name relationship phone phone_2 email language))

    case Enrollment.add_guardian(socket.assigns.current_scope, socket.assigns.student, attrs) do
      {:ok, _guardian} ->
        {:noreply, socket |> assign(match: []) |> assign_guardian_form(%{}) |> load()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
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
      {:noreply, socket |> assign(match: []) |> assign_guardian_form(%{}) |> load()}
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="student" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Élève")} title={@student.full_name}>
          <:actions>
            <.link
              :if={@access == :manage}
              navigate={~p"/school/students"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-left" class="size-4" /> {gettext("Élèves")}
            </.link>
          </:actions>
        </.page_header>

        <div class="grid gap-4 lg:grid-cols-2">
          <article id="student-identity" class="ta-panel flex flex-col gap-3">
            <header class="flex items-center justify-between">
              <h2 class="ta-eyebrow">{gettext("Identité")}</h2>
              <button
                :if={@access == :manage and not @editing}
                id="edit-identity"
                phx-click="edit_identity"
                class="btn btn-ghost btn-xs"
              >
                <.icon name="hero-pencil-square" class="size-4" /> {gettext("Modifier")}
              </button>
            </header>

            <.form
              :if={@editing}
              for={@identity_form}
              id="identity-form"
              phx-submit="save_identity"
              class="grid gap-2 sm:grid-cols-2"
            >
              <.input field={@identity_form[:full_name]} label={gettext("Nom et prénoms")} />
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
              <div class="flex items-end gap-2">
                <button class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
                <button type="button" phx-click="cancel_identity" class="btn btn-ghost btn-sm">{gettext(
                  "Annuler"
                )}</button>
              </div>
            </.form>

            <dl :if={not @editing} class="grid grid-cols-2 gap-2 text-sm">
              <div class="col-span-2">
                <dt class="ta-eyebrow">{gettext("Nom et prénoms")}</dt><dd>{@student.full_name}</dd>
              </div>
              <div>
                <dt class="ta-eyebrow">{gettext("Sexe")}</dt><dd>{Sex.label(@student.sex)}</dd>
              </div>
              <div>
                <dt class="ta-eyebrow">{gettext("Matricule")}</dt><dd>{@student.matricule || "—"}</dd>
              </div>
              <div>
                <dt class="ta-eyebrow">{gettext("Date de naissance")}</dt><dd>
                  {format_date(@student.birth_date)}
                </dd>
              </div>
              <div>
                <dt class="ta-eyebrow">{gettext("Lieu de naissance")}</dt><dd>
                  {@student.birth_place || "—"}
                </dd>
              </div>
            </dl>
          </article>

          <article id="student-guardians" class="ta-panel flex flex-col gap-3">
            <h2 class="ta-eyebrow">{gettext("Parents et tuteurs")}</h2>
            <p
              :if={@links != [] and not Enum.any?(@links, & &1.primary_contact)}
              class="text-sm text-warning"
            >
              {gettext("Aucun contact principal")}
            </p>
            <ul id="guardian-list" class="flex flex-col divide-y divide-base-300">
              <li
                :for={l <- @links}
                id={"guardian-#{l.id}"}
                class="flex flex-wrap items-center gap-2 py-2"
              >
                <span class="font-semibold">{l.guardian.full_name}</span>
                <span class="text-base-content/60">{GuardianRelationship.label(
                  l.guardian.relationship
                )}</span>
                <span :if={l.primary_contact} class="badge badge-primary badge-sm">{gettext(
                  "Contact principal"
                )}</span>
                <a href={"tel:#{l.guardian.phone_key}"} class="link link-primary font-mono text-xs">{l.guardian.phone}</a>
                <span :if={l.guardian.phone_2} class="font-mono text-xs">{l.guardian.phone_2}</span>
                <span :if={l.guardian.email} class="text-xs">{l.guardian.email}</span>
                <span class="text-xs text-base-content/60">{ContactLanguage.label(l.guardian.language)}</span>
                <span :if={@access == :manage} class="ml-auto flex gap-1">
                  <button
                    id={"edit-guardian-#{l.id}"}
                    phx-click="edit_guardian"
                    phx-value-id={l.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Modifier")}
                  </button>
                  <button
                    :if={not l.primary_contact}
                    id={"make-primary-#{l.id}"}
                    phx-click="make_primary"
                    phx-value-id={l.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Contact principal")}
                  </button>
                  <button
                    id={"unlink-#{l.id}"}
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
              class="grid gap-2 rounded-box border border-base-300 p-3 sm:grid-cols-2"
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
                label={gettext("Langue")}
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
              :if={@access == :manage}
              for={@guardian_form}
              id="guardian-form"
              phx-change="guardian_change"
              phx-submit="add_guardian"
              class="grid gap-2 sm:grid-cols-2"
            >
              <.input field={@guardian_form[:phone]} label={gettext("Téléphone")} phx-debounce="300" />
              <.input field={@guardian_form[:full_name]} label={gettext("Nom et prénoms")} />
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
                label={gettext("Langue")}
                options={Enum.map(ContactLanguage.values(), &{ContactLanguage.label(&1), &1})}
              />
              <div
                :if={@match != []}
                id="guardian-match"
                class="sm:col-span-2 flex flex-col gap-1 rounded-box bg-base-200 p-2 text-sm"
              >
                <span :for={g <- @match} class="flex items-center gap-2">
                  {gettext("Déjà enregistré :")} <strong>{g.full_name}</strong>
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
              <button class="btn btn-primary btn-sm sm:col-span-2">{gettext("Ajouter le parent")}</button>
            </.form>
          </article>
        </div>

        <article id="student-history" class="ta-panel flex flex-col gap-2">
          <h2 class="ta-eyebrow">{gettext("Scolarité")}</h2>
          <table class="table table-sm">
            <tbody>
              <tr :for={e <- @history}>
                <td>{e.academic_year.name}</td>
                <td>{e.class_group.label}</td>
                <td>
                  <span :if={e.repeater} class="badge badge-ghost badge-sm">{gettext("Redoublant")}</span>
                </td>
                <td>
                  <span :if={d = @decisions[e.class_group_id]}>{PassageDecision.label(d)}</span>
                </td>
                <td class="text-right">
                  <.link
                    navigate={~p"/school/classes/#{e.class_group_id}/students/#{e.id}/bulletin"}
                    class="link link-primary text-sm"
                  >
                    {gettext("Bulletin")}
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </article>

        <article :if={@this_year} id="student-this-year" class="ta-panel flex flex-col gap-3">
          <h2 class="ta-eyebrow">{gettext("Cette année")}</h2>
          <dl class="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
            <div>
              <dt class="ta-eyebrow">{gettext("Absences non justifiées")}</dt><dd>
                {@this_year.attendance.unjustified_hours} h
              </dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Absences justifiées")}</dt><dd>
                {@this_year.attendance.justified_hours} h
              </dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Retards")}</dt><dd>{@this_year.attendance.retards}</dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Consignes")}</dt><dd>
                {@this_year.discipline.consignes_count}
              </dd>
            </div>
          </dl>
          <ul class="text-sm">
            <li :for={s <- @this_year.discipline.sanctions}>
              {format_date(s.date)} · {TeacherAssistant.Academics.SanctionType.label(s.type)}
              <span :if={s.reason} class="text-base-content/60">— {s.reason}</span>
            </li>
          </ul>
          <p class="text-sm">
            {gettext("Conduite")} :
            <span :for={{seq, value} <- @this_year.conduct} class="mr-3">
              {gettext("Séq. %{n}", n: seq.number)} <strong>{value || "—"}</strong>
            </span>
          </p>
          <p class="flex gap-3 text-sm">
            <.link
              navigate={~p"/school/classes/#{@this_year.enrollment.class_group_id}/register"}
              class="link link-primary"
            >
              {gettext("Registre d'appel")}
            </.link>
            <.link
              navigate={~p"/school/classes/#{@this_year.enrollment.class_group_id}/discipline"}
              class="link link-primary"
            >
              {gettext("Discipline")}
            </.link>
          </p>
        </article>
      </section>
    </Layouts.app>
    """
  end
end
