defmodule TeacherAssistantWeb.School.ClassLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace) do
      {:ok,
       socket
       |> assign(cg: cg, admin?: Permissions.admin?(scope), search_results: [], q: "")
       |> load_roster()}
    else
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

        <div class="overflow-x-auto">
          <table id="class-roster" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Nom")}</th>
                <th>{gettext("Sexe")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Statut")}</th>
                <th>{gettext("Redoublant")}</th>
                <th :if={@admin?}><span class="sr-only">{gettext("Actions")}</span></th>
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
                <td :if={@admin?}>
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

        <div :if={@admin?} class="ta-leaf space-y-3">
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
        |> Enum.reject(&(&1.id == cg.id))
    )
  end

  def handle_event("enroll_new", %{"student" => params}, socket) do
    with true <- socket.assigns.admin? do
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
      if socket.assigns.admin?,
        do: Enrollments.search_students(socket.assigns.current_scope.current_workspace, q),
        else: []

    {:noreply, assign(socket, search_results: results, q: q)}
  end

  def handle_event("enroll_existing", %{"student-id" => sid}, socket) do
    with true <- socket.assigns.admin?,
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
    with true <- socket.assigns.admin?,
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
    with true <- socket.assigns.admin?,
         %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)) do
      :ok = Enrollments.withdraw(e)
      {:noreply, socket |> put_flash(:info, gettext("Enrollment removed.")) |> load_roster()}
    else
      _ -> {:noreply, socket}
    end
  end

  defp parse_sex("m"), do: :m
  defp parse_sex(_), do: :f
  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v
end
