defmodule TeacherAssistantWeb.School.ClassLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Enrollments}
  alias TeacherAssistant.Accounts.{Permissions, Schools}

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         admin?: Permissions.admin?(scope),
         manage?: true,
         register_link?:
           Permissions.conduct_manager?(scope) or Permissions.admin_or_form_master?(scope, cg),
         discipline_link?:
           Permissions.conduct_manager?(scope) or Permissions.admin_or_form_master?(scope, cg),
         fees_link?:
           Permissions.fees_manager?(scope) or Permissions.admin_or_form_master?(scope, cg),
         search_results: [],
         q: ""
       )
       |> load_roster()}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
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
          <.link
            :if={@fees_link?}
            navigate={~p"/school/classes/#{@cg.id}/fees"}
            id="go-to-fees"
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="hero-banknotes" class="size-4" />
            {gettext("Frais")}
          </.link>
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
                    {if row.enrollment.status == :reinscription,
                      do: gettext("Réinscription"),
                      else: gettext("Inscription")}
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
                <option value="f">{gettext("Féminin")}</option>
                <option value="m">{gettext("Masculin")}</option>
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

          <form :if={@admin?} id="form-master-form" phx-change="set_form_master" class="text-sm">
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
                  <th :if={@admin?}><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={tc <- @assignments} id={"assignment-row-#{tc.id}"}>
                  <td>{tc.subject}</td>
                  <td>{tc.teacher.email}</td>
                  <td>{tc.weekly_hours}</td>
                  <td>
                    <form id={"coefficient-#{tc.id}"} phx-change="set_coefficient">
                      <input type="hidden" name="context-id" value={tc.id} />
                      <input
                        type="number"
                        step="0.5"
                        min="0"
                        name="coefficient"
                        value={Decimal.to_string(tc.coefficient)}
                        class="input input-bordered input-xs w-20"
                        disabled={!@admin?}
                      />
                    </form>
                  </td>
                  <td :if={@admin?}>
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

          <form :if={@admin?} id="assign-form" phx-submit="assign" class="space-y-2">
            <div class="grid gap-2 sm:grid-cols-5">
              <select name="assignment[user_id]" class="select select-bordered select-sm">
                <option :for={m <- @members} value={m.user_id}>{m.user.email}</option>
              </select>
              <input
                type="text"
                name="assignment[subject]"
                placeholder={gettext("Matière")}
                class="input input-bordered input-sm"
              />
              <input
                type="number"
                name="assignment[weekly_hours]"
                value="4"
                min="1"
                max="40"
                placeholder={gettext("H/semaine")}
                class="input input-bordered input-sm"
              />
              <input
                type="number"
                name="assignment[coefficient]"
                value="1"
                min="0"
                step="0.5"
                placeholder={gettext("Coefficient")}
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

    assign(socket,
      roster: Academics.list_roster(cg),
      other_classes:
        Academics.list_class_groups(scope.current_workspace, scope.current_academic_year)
        |> Enum.reject(&(&1.id == cg.id)),
      assignments: Assignments.list_for_class(cg),
      members: Schools.list_members(scope.current_workspace)
    )
  end

  def handle_event("enroll_new", %{"student" => params}, socket) do
    with true <- socket.assigns.manage? do
      case Enrollments.enroll_new(socket.assigns.cg, %{
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
        do: Enrollments.search_students(socket.assigns.current_scope.current_workspace, q),
        else: []

    {:noreply, assign(socket, search_results: results, q: q)}
  end

  def handle_event("enroll_existing", %{"student-id" => sid}, socket) do
    with true <- socket.assigns.manage?,
         %{} = student <- Enum.find(socket.assigns.search_results, &(&1.id == sid)) do
      case Enrollments.enroll_existing(socket.assigns.cg, student) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Student re-enrolled."))
           |> assign(search_results: [], q: "")
           |> load_roster()}

        {:error, :already_enrolled} ->
          {:noreply,
           put_flash(socket, :error, gettext("This student is already enrolled this year."))}
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
         {:ok, _} <- Enrollments.transfer(e, target) do
      {:noreply, socket |> put_flash(:info, gettext("Student transferred.")) |> load_roster()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("withdraw", %{"enrollment-id" => eid}, socket) do
    with true <- socket.assigns.manage?,
         %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)) do
      :ok = Enrollments.withdraw(e)
      {:noreply, socket |> put_flash(:info, gettext("Enrollment removed.")) |> load_roster()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("assign", %{"assignment" => params}, socket) do
    with true <- socket.assigns.admin?,
         %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == params["user_id"])) do
      case Assignments.assign(socket.assigns.cg, member.user, %{
             subject: params["subject"],
             weekly_hours: parse_hours(params["weekly_hours"]),
             coefficient: parse_coef(params["coefficient"])
           }) do
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
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unassign", %{"context-id" => cid}, socket) do
    with true <- socket.assigns.admin?,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      case Assignments.remove(tc) do
        :ok ->
          {:noreply, socket |> put_flash(:info, gettext("Assignment removed.")) |> load_roster()}

        {:error, :has_data} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("This assignment has marks or progressions — it cannot be removed.")
           )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_coefficient", %{"context-id" => cid, "coefficient" => value}, socket) do
    with true <- socket.assigns.admin?,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         {:ok, _} <- Assignments.set_coefficient(tc, value) do
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_roster()}
    else
      {:error, :invalid_coefficient} ->
        {:noreply, put_flash(socket, :error, gettext("Enter a positive coefficient."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reassign", %{"context-id" => cid, "user_id" => uid}, socket) do
    with true <- socket.assigns.admin?,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == uid)),
         {:ok, _} <- Assignments.reassign(tc, member.user) do
      {:noreply, socket |> put_flash(:info, gettext("Teacher reassigned.")) |> load_roster()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_form_master", %{"user_id" => uid}, socket) do
    with true <- socket.assigns.admin? do
      target =
        if uid == "", do: :clear, else: Enum.find(socket.assigns.members, &(&1.user_id == uid))

      case target do
        :clear ->
          {:ok, cg} = Academics.set_form_master(socket.assigns.cg, nil)

          {:noreply,
           socket |> assign(cg: cg) |> put_flash(:info, gettext("Form master cleared."))}

        %{user_id: user_id} ->
          {:ok, cg} = Academics.set_form_master(socket.assigns.cg, user_id)

          {:noreply,
           socket |> assign(cg: cg) |> put_flash(:info, gettext("Form master assigned."))}

        _ ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp parse_hours(v) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 and n <= 40 -> n
      _ -> 4
    end
  end

  defp parse_coef(value) do
    case Decimal.parse(String.trim(to_string(value))) do
      {dec, ""} -> if Decimal.positive?(dec), do: dec, else: Decimal.new(1)
      _ -> Decimal.new(1)
    end
  end

  defp parse_sex("m"), do: :m
  defp parse_sex(_), do: :f
  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v
end
