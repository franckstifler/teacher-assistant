defmodule TeacherAssistantWeb.School.ClassLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment

  alias TeacherAssistant.Academics.{EnrollmentStatus, Sex}
  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :students) || {:elsewhere, cg} do
      {:ok,
       socket
       |> assign(
         cg: cg,
         can_manage_classes?: Enrollment.can_manage_classes?(scope),
         manage?: true,
         search_results: [],
         q: ""
       )
       |> load_roster()}
    else
      # Spec 2026-10-08 §3: a viewer who may open another tab of the class lands there.
      {:elsewhere, cg} ->
        case ClassShell.load(scope, cg).tabs do
          [{_tab, path} | _] -> {:ok, push_navigate(socket, to: path)}
          [] -> {:ok, push_navigate(socket, to: ~p"/school")}
        end

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:students}>
        <:actions>
          <.link
            navigate={~p"/school/bulletins?class=#{@cg.id}"}
            id="go-to-bulletins"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Bulletins")}
          </.link>
          <.link
            :if={@can_manage_classes?}
            navigate={~p"/school/classes/#{@cg.id}/import"}
            id="go-to-import"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Importer une liste")}
          </.link>
        </:actions>

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
                <td>
                  <.link navigate={~p"/school/students/#{row.student.id}"} class="hover:text-primary">
                    {row.student.full_name}
                  </.link>
                </td>
                <td>{row.student.sex && TeacherAssistant.Academics.Sex.label(row.student.sex)}</td>
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
      </.class_shell>
    </Layouts.app>
    """
  end

  defp load_roster(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg

    socket
    |> assign(
      roster: Enrollment.list_roster(scope, cg),
      other_classes:
        Enrollment.list_class_groups(scope, scope.current_academic_year)
        |> Enum.reject(&(&1.id == cg.id))
    )
    |> ClassShell.assign_shell()
  end

  def handle_event("enroll_new", %{"student" => params}, socket) do
    with true <- socket.assigns.manage? do
      case Enrollment.enroll_new(socket.assigns.current_scope, socket.assigns.cg, %{
             full_name: params["full_name"],
             sex: parse_sex(params["sex"]),
             matricule: presence(params["matricule"]),
             repeater: params["repeater"] == "true"
           }) do
        {:ok, _} ->
          socket = load_roster(socket)

          # Spec KLM5: over the maximum is a warning, never a block.
          message =
            if socket.assigns.shell.capacity.over?,
              do:
                gettext("Élève inscrit. La classe dépasse l'effectif maximum (%{max}).",
                  max: socket.assigns.shell.capacity.max
                ),
              else: gettext("Student enrolled.")

          {:noreply, put_flash(socket, :info, message)}

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

  defp parse_sex("m"), do: :m
  defp parse_sex(_), do: :f
  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v
end
