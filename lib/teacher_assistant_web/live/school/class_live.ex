defmodule TeacherAssistantWeb.School.ClassLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment

  alias TeacherAssistant.Academics.{EnrollmentStatus, Sex}
  alias TeacherAssistant.Curriculum

  alias TeacherAssistant.Accounts

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Enrollment.class_manager?(scope, cg) do
      subject_options = Curriculum.subjects_taught_in(scope, cg)

      {:ok,
       socket
       |> assign(
         cg: cg,
         can_manage_classes?: Enrollment.can_manage_classes?(scope),
         can_manage_assignments?: Curriculum.can_manage_assignments?(scope),
         manage?: true,
         register_link?:
           TeacherAssistant.Discipline.can_manage_conduct?(scope) or
             Enrollment.class_manager?(scope, cg),
         discipline_link?:
           TeacherAssistant.Discipline.can_manage_conduct?(scope) or
             Enrollment.class_manager?(scope, cg),
         search_results: [],
         q: "",
         subject_options: subject_options,
         class_coefficients_allowed?: class_coefficients_allowed?(scope)
       )
       |> load_roster()}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="class-detail" class="space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{@cg.level}#{if @cg.serie, do: " · #{@cg.serie}", else: ""}"}
        />

        <div :if={@manage?} class="flex justify-end gap-2">
          <.link
            navigate={~p"/school/classes/#{@cg.id}/results"}
            id="go-to-results"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-chart-bar" class="size-4" />
            {gettext("Résultats & bulletins")}
          </.link>
          <.link
            navigate={~p"/school/classes/#{@cg.id}/import"}
            id="go-to-import"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-arrow-up-tray" class="size-4" />
            {gettext("Import students")}
          </.link>
          <.link
            navigate={~p"/school/classes/#{@cg.id}/timetable"}
            id="go-to-timetable"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-calendar-days" class="size-4" />
            {gettext("Emploi du temps")}
          </.link>
          <.link
            :if={@register_link?}
            navigate={~p"/school/classes/#{@cg.id}/register"}
            id="go-to-register"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-clipboard-document-check" class="size-4" />
            {gettext("Cahier d'appel")}
          </.link>
          <.link
            :if={@discipline_link?}
            navigate={~p"/school/classes/#{@cg.id}/discipline"}
            id="go-to-discipline"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-shield-exclamation" class="size-4" />
            {gettext("Discipline")}
          </.link>
          <%!-- Fees link removed: bursar features are deferred (docs/audits/2026-09-23-school-focus/README.md §2). Route /school/classes/:id/fees stays. --%>
        </div>

        <div class="overflow-x-auto">
          <table id="class-roster" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Nom")}</th>
                <th>{gettext("Sexe")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Statut")}</th>
                <th>{gettext("Redoublant")}</th>
                <th :if={@manage?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @roster} id={"roster-row-#{row.enrollment.id}"}>
                <td>{row.student.full_name}</td>
                <td>{row.student.sex}</td>
                <td>{row.student.matricule}</td>
                <td>
                  <span class="badge badge-sm">
                    {EnrollmentStatus.label(row.enrollment.status)}
                  </span>
                </td>
                <td>
                  <span :if={row.enrollment.repeater} class="badge badge-sm badge-warning">
                    {gettext("Redoublant")}
                  </span>
                </td>
                <td :if={@manage?}>
                  <div class="flex items-center gap-2">
                    <form
                      id={"transfer-#{row.enrollment.id}"}
                      phx-change="transfer"
                      class="inline"
                    >
                      <input type="hidden" name="enrollment-id" value={row.enrollment.id} />
                      <select name="class_group_id" class="select select-bordered select-xs">
                        <option value="">{gettext("Transférer vers…")}</option>
                        <option :for={oc <- @other_classes} value={oc.id}>{oc.label}</option>
                      </select>
                    </form>
                    <button
                      id={"withdraw-#{row.enrollment.id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="withdraw"
                      phx-value-enrollment-id={row.enrollment.id}
                      data-confirm={gettext("Retirer cet élève de la classe ?")}
                    >
                      {gettext("Retirer")}
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.empty_state
          :if={@roster == []}
          icon="hero-user-group"
          title={gettext("Aucun élève inscrit")}
        />

        <div :if={@manage?} class="ta-leaf space-y-3">
          <h2 class="text-sm font-semibold">{gettext("Inscrire un nouvel élève")}</h2>
          <form id="enroll-form" phx-submit="enroll_new" class="space-y-2">
            <div class="grid gap-2 sm:grid-cols-4">
              <input
                type="text"
                name="student[full_name]"
                placeholder={gettext("Nom complet")}
                class="input input-bordered input-sm"
              />
              <select name="student[sex]" class="select select-bordered select-sm">
                <option :for={s <- [:f, :m]} value={s}>{Sex.label(s)}</option>
              </select>
              <input
                type="text"
                name="student[matricule]"
                placeholder={gettext("Matricule (optionnel)")}
                class="input input-bordered input-sm"
              />
              <label class="label cursor-pointer justify-start gap-2">
                <input
                  type="checkbox"
                  name="student[repeater]"
                  value="true"
                  class="checkbox checkbox-sm"
                />
                <span class="text-xs">{gettext("Redoublant")}</span>
              </label>
            </div>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Inscrire")}</button>
          </form>

          <div class="pt-4">
            <h2 class="text-sm font-semibold">{gettext("Rechercher un élève existant")}</h2>
            <input
              type="text"
              id="enroll-search"
              name="q"
              value={@q}
              phx-change="search"
              phx-debounce="300"
              placeholder={gettext("Nom ou matricule")}
              class="input input-bordered input-sm w-full sm:w-64"
            />
            <ul id="search-results" class="mt-2 space-y-1">
              <li
                :for={student <- @search_results}
                class="flex items-center justify-between gap-3 rounded-lg border border-base-300 px-3 py-2"
              >
                <span class="text-sm">
                  {student.full_name}
                  <span :if={student.matricule} class="text-base-content/60">
                    — {student.matricule}
                  </span>
                </span>
                <button
                  id={"search-enroll-#{student.id}"}
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="enroll_existing"
                  phx-value-student-id={student.id}
                >
                  {gettext("Réinscrire")}
                </button>
              </li>
            </ul>
          </div>
        </div>

        <div class="ta-leaf space-y-3">
          <h2 class="text-sm font-semibold">{gettext("Enseignements")}</h2>

          <form
            :if={@can_manage_classes?}
            id="form-master-form"
            phx-change="set_form_master"
            class="text-sm"
          >
            <label class="ta-eyebrow block mb-1">{gettext("Professeur principal")}</label>
            <select name="user_id" class="select select-bordered select-sm w-full sm:w-80">
              <option value="">{gettext("Aucun")}</option>
              <option
                :for={m <- @members}
                value={m.user_id}
                selected={m.user_id == @cg.form_master_user_id}
              >
                {m.user.email}
              </option>
            </select>
          </form>

          <div class="overflow-x-auto">
            <table id="assignments" class="table table-zebra">
              <thead>
                <tr>
                  <th>{gettext("Matière")}</th>
                  <th>{gettext("Enseignant")}</th>
                  <th>{gettext("H/semaine")}</th>
                  <th>{gettext("Coefficient")}</th>
                  <th :if={@can_manage_assignments?}>{gettext("Regroupement")}</th>
                  <th :if={@can_manage_assignments?}>
                    <span class="sr-only">{gettext("Actions")}</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={tc <- @assignments} id={"assignment-row-#{tc.id}"}>
                  <td>
                    {tc.subject}
                    <details
                      :if={tc.catalog_subject.optional?}
                      id={"takers-#{tc.id}"}
                      class="mt-1 text-xs"
                    >
                      <summary class="cursor-pointer text-base-content/70">
                        {gettext("Élèves concernés")}
                        <span class="ta-num">
                          ({length(@roster_students) -
                            MapSet.size(Map.get(@exemptions, tc.id, MapSet.new()))}/{length(
                            @roster_students
                          )})
                        </span>
                      </summary>
                      <form
                        :if={@can_manage_assignments?}
                        id={"takers-form-#{tc.id}"}
                        phx-submit="set_takers"
                        class="mt-2 space-y-1"
                      >
                        <input type="hidden" name="context-id" value={tc.id} />
                        <input type="hidden" name="takers[]" value="" />
                        <label :for={s <- @roster_students} class="flex items-center gap-2">
                          <input
                            type="checkbox"
                            name="takers[]"
                            value={s.id}
                            checked={
                              not MapSet.member?(Map.get(@exemptions, tc.id, MapSet.new()), s.id)
                            }
                            class="checkbox checkbox-xs"
                          />
                          {s.full_name}
                        </label>
                        <button type="submit" class="btn btn-ghost btn-xs">{gettext("Enregistrer")}</button>
                      </form>
                    </details>
                  </td>
                  <td>{tc.teacher.email}</td>
                  <td>{tc.weekly_hours}</td>
                  <td>
                    <form
                      :if={@can_manage_assignments? and @class_coefficients_allowed?}
                      id={"coefficient-#{tc.id}"}
                      phx-change="set_coefficient"
                      class="flex items-center gap-1"
                    >
                      <input type="hidden" name="context-id" value={tc.id} />
                      <input
                        type="text"
                        inputmode="decimal"
                        name="coefficient"
                        value={fmt_coef(tc.effective_coefficient)}
                        class={[
                          "input input-bordered input-xs w-16",
                          tc.coefficient && "border-warning"
                        ]}
                      />
                      <span
                        :if={tc.coefficient && tc.grid_coefficient}
                        class="text-xs text-base-content/60"
                      >
                        {gettext("modèle : %{value}",
                          value: fmt_coef(tc.grid_coefficient.coefficient)
                        )}
                      </span>
                      <button
                        :if={tc.coefficient}
                        id={"reset-coefficient-#{tc.id}"}
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="reset_coefficient"
                        phx-value-context-id={tc.id}
                      >
                        {gettext("Revenir au modèle")}
                      </button>
                    </form>
                    <span
                      :if={!(@can_manage_assignments? and @class_coefficients_allowed?)}
                      class="ta-num"
                    >
                      {fmt_coef(tc.effective_coefficient)}
                    </span>
                    <span
                      :if={!tc.taught_here?}
                      id={"not-taught-#{tc.id}"}
                      class="badge badge-warning badge-sm mt-1"
                    >
                      {gettext("Non enseignée à ce niveau selon la grille")}
                    </span>
                  </td>
                  <td :if={@can_manage_assignments?}>
                    <div :if={tc.combined_course_id} class="flex items-center gap-2">
                      <span class="badge badge-sm badge-info">
                        {tc.combined_course.label}
                      </span>
                      <button
                        id={"split-#{tc.id}"}
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="split_course"
                        phx-value-context-id={tc.id}
                        data-confirm={gettext("Séparer cet enseignement combiné ?")}
                      >
                        {gettext("Séparer")}
                      </button>
                    </div>
                    <form
                      :if={!tc.combined_course_id && Map.get(@combinable_siblings, tc.id, []) != []}
                      id={"teach-together-#{tc.id}"}
                      phx-submit="teach_together"
                      class="flex items-center gap-2"
                    >
                      <input type="hidden" name="context-id" value={tc.id} />
                      <select name="sibling-ids[]" multiple class="select select-bordered select-xs">
                        <option :for={sib <- Map.get(@combinable_siblings, tc.id, [])} value={sib.id}>
                          {sib.class_group.label}
                        </option>
                      </select>
                      <button type="submit" class="btn btn-ghost btn-xs">
                        {gettext("Enseigner ensemble")}
                      </button>
                    </form>
                  </td>
                  <td :if={@can_manage_assignments?}>
                    <div class="flex items-center gap-2">
                      <form
                        id={"reassign-#{tc.id}"}
                        phx-change="reassign"
                        class="inline"
                      >
                        <input type="hidden" name="context-id" value={tc.id} />
                        <select name="user_id" class="select select-bordered select-xs">
                          <option value="">{gettext("Réassigner à…")}</option>
                          <option :for={m <- @members} value={m.user_id}>{m.user.email}</option>
                        </select>
                      </form>
                      <button
                        id={"unassign-#{tc.id}"}
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="unassign"
                        phx-value-context-id={tc.id}
                        data-confirm={gettext("Retirer cette affectation ?")}
                      >
                        {gettext("Retirer")}
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <.empty_state
            :if={@assignments == []}
            icon="hero-academic-cap"
            title={gettext("Aucun enseignant affecté")}
          />

          <form :if={@can_manage_assignments?} id="assign-form" phx-submit="assign" class="space-y-2">
            <div class="grid gap-2 sm:grid-cols-4">
              <select name="assignment[user_id]" class="select select-bordered select-sm">
                <option :for={m <- @members} value={m.user_id}>{m.user.email}</option>
              </select>
              <select name="assignment[subject]" class="select select-bordered select-sm">
                <option value="">{gettext("Choisir une matière")}</option>
                <option :for={s <- @subject_options} value={s.name}>{s.name}</option>
              </select>
              <input
                type="number"
                name="assignment[weekly_hours]"
                value="4"
                min="1"
                max="40"
                placeholder={gettext("H/semaine")}
                class="input input-bordered input-sm"
              />
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Affecter")}</button>
            </div>
          </form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_roster(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg
    assignments = Curriculum.list_assignments_for_class(scope, cg)

    assign(socket,
      roster: Enrollment.list_roster(scope, cg),
      other_classes:
        Enrollment.list_class_groups(scope, scope.current_academic_year)
        |> Enum.reject(&(&1.id == cg.id)),
      assignments: assignments,
      combinable_siblings:
        combinable_siblings_by_context(
          scope,
          assignments,
          socket.assigns[:can_manage_assignments?]
        ),
      members: Accounts.list_members(scope),
      roster_students: Enrollment.list_students(scope, cg),
      exemptions:
        for(
          tc <- assignments,
          tc.catalog_subject.optional?,
          into: %{},
          do: {tc.id, Curriculum.exempt_student_ids(scope, tc)}
        )
    )
  end

  defp combinable_siblings_by_context(scope, assignments, true) do
    assignments
    |> Enum.reject(& &1.combined_course_id)
    |> Map.new(&{&1.id, Curriculum.combinable_siblings(scope, &1)})
  end

  defp combinable_siblings_by_context(_scope, _assignments, _admin?), do: %{}

  def handle_event("enroll_new", %{"student" => params}, socket) do
    with true <- socket.assigns.manage? do
      case Enrollment.enroll_new(socket.assigns.current_scope, socket.assigns.cg, %{
             full_name: params["full_name"],
             sex: parse_sex(params["sex"]),
             matricule: presence(params["matricule"]),
             repeater: params["repeater"] == "true"
           }) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, gettext("Student enrolled.")) |> load_roster()}

        {:error, :duplicate_matricule} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("This matricule already belongs to another student.")
           )}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not enroll the student."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    results =
      if socket.assigns.manage?,
        do: Enrollment.search_students(socket.assigns.current_scope, q),
        else: []

    {:noreply, assign(socket, search_results: results, q: q)}
  end

  def handle_event("enroll_existing", %{"student-id" => sid}, socket) do
    with true <- socket.assigns.manage?,
         %{} = student <- Enum.find(socket.assigns.search_results, &(&1.id == sid)) do
      case Enrollment.enroll_existing(socket.assigns.current_scope, socket.assigns.cg, student) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Student re-enrolled."))
           |> assign(search_results: [], q: "")
           |> load_roster()}

        {:error, :already_enrolled} ->
          {:noreply,
           put_flash(socket, :error, gettext("This student is already enrolled this year."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not enroll the student."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("transfer", %{"enrollment-id" => eid, "class_group_id" => cgid}, socket) do
    with true <- socket.assigns.manage?,
         true <- cgid != "",
         %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         %{} = target <- Enum.find(socket.assigns.other_classes, &(&1.id == cgid)),
         {:ok, _} <- Enrollment.transfer(socket.assigns.current_scope, e, target) do
      {:noreply, socket |> put_flash(:info, gettext("Student transferred.")) |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("withdraw", %{"enrollment-id" => eid}, socket) do
    with true <- socket.assigns.manage?,
         %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         :ok <- Enrollment.withdraw(socket.assigns.current_scope, e) do
      {:noreply, socket |> put_flash(:info, gettext("Enrollment removed.")) |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("assign", %{"assignment" => params}, socket) do
    with %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == params["user_id"])) do
      case Curriculum.assign_teacher(
             socket.assigns.current_scope,
             socket.assigns.cg,
             member.user,
             %{
               subject: params["subject"],
               weekly_hours: parse_hours(params["weekly_hours"])
             }
           ) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, gettext("Teacher assigned.")) |> load_roster()}

        {:error, :already_assigned} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("This class already has a teacher for this subject.")
           )}

        {:error, :not_assignable} ->
          {:noreply, put_flash(socket, :error, gettext("This member cannot be assigned."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not assign the teacher."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unassign", %{"context-id" => cid}, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      case Curriculum.remove_assignment(socket.assigns.current_scope, tc) do
        :ok ->
          {:noreply, socket |> put_flash(:info, gettext("Assignment removed.")) |> load_roster()}

        {:error, :has_data} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("This assignment has marks or progressions — it cannot be removed.")
           )}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_coefficient", %{"context-id" => cid, "coefficient" => value}, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         {:ok, _} <-
           Curriculum.set_assignment_coefficient(socket.assigns.current_scope, tc, value) do
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_coefficient} ->
        {:noreply, put_flash(socket, :error, gettext("Enter a positive coefficient."))}

      {:error, :class_coefficients_disabled} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Les coefficients propres à une classe sont désactivés.")
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reset_coefficient", %{"context-id" => cid}, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         {:ok, _} <- Curriculum.clear_assignment_coefficient(socket.assigns.current_scope, tc) do
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_takers", %{"context-id" => cid} = params, socket) do
    takers = params |> Map.get("takers", []) |> Enum.reject(&(&1 == ""))

    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      case Curriculum.set_exemptions(socket.assigns.current_scope, tc, takers) do
        :ok ->
          {:noreply,
           socket |> put_flash(:info, gettext("Élèves concernés enregistrés.")) |> load_roster()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Liste non enregistrée."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reassign", %{"context-id" => cid, "user_id" => uid}, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == uid)),
         {:ok, _} <- Curriculum.reassign_teacher(socket.assigns.current_scope, tc, member.user) do
      {:noreply, socket |> put_flash(:info, gettext("Teacher reassigned.")) |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_form_master", %{"user_id" => uid}, socket) do
    with true <- socket.assigns.can_manage_classes? do
      target =
        if uid == "", do: :clear, else: Enum.find(socket.assigns.members, &(&1.user_id == uid))

      case target do
        :clear ->
          {:ok, cg} =
            Enrollment.set_form_master(socket.assigns.current_scope, socket.assigns.cg, nil)

          {:noreply,
           socket |> assign(cg: cg) |> put_flash(:info, gettext("Form master cleared."))}

        %{user_id: user_id} ->
          {:ok, cg} =
            Enrollment.set_form_master(socket.assigns.current_scope, socket.assigns.cg, user_id)

          {:noreply,
           socket |> assign(cg: cg) |> put_flash(:info, gettext("Form master assigned."))}

        _ ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("teach_together", %{"context-id" => cid} = params, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      sibling_ids = List.wrap(params["sibling-ids"])

      siblings =
        socket.assigns.combinable_siblings
        |> Map.get(cid, [])
        |> Enum.filter(&(&1.id in sibling_ids))

      case Curriculum.combine_course(socket.assigns.current_scope, [tc | siblings]) do
        {:ok, _course} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("These classes are now taught together."))
           |> load_roster()}

        {:error, :need_two} ->
          {:noreply, put_flash(socket, :error, gettext("Pick at least one other class."))}

        {:error, :teacher_mismatch} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("These assignments don't share the same teacher.")
           )}

        {:error, :subject_mismatch} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("These assignments don't share the same subject.")
           )}

        {:error, :already_combined} ->
          {:noreply,
           put_flash(socket, :error, gettext("One of these classes is already combined."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not combine these classes."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("split_course", %{"context-id" => cid}, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         course_id when not is_nil(course_id) <- tc.combined_course_id,
         {:ok, course} <- Curriculum.get_course(socket.assigns.current_scope, course_id),
         :ok <- Curriculum.split_course(socket.assigns.current_scope, course) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("These classes are now taught separately."))
       |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  defp parse_hours(v) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 and n <= 40 -> n
      _ -> 4
    end
  end

  defp parse_sex("m"), do: :m
  defp parse_sex(_), do: :f
  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v

  defp class_coefficients_allowed?(scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.class_coefficients_allowed?
      _ -> false
    end
  end

  defp fmt_coef(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
end
