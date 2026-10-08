defmodule TeacherAssistantWeb.School.TeachingsLive do
  @moduledoc """
  The class's Enseignements tab (spec 2026-10-08 §5): form master, the class's
  assignments (teacher, hours, coefficient, takers, combined courses) and the
  form to add one.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Curriculum, Enrollment}
  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :teachings) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         can_manage_classes?: Enrollment.can_manage_classes?(scope),
         can_manage_assignments?: Curriculum.can_manage_assignments?(scope),
         subject_options: Curriculum.subjects_taught_in(scope, cg),
         on_grid?: Curriculum.class_on_grid?(scope, cg),
         class_coefficients_allowed?: class_coefficients_allowed?(scope),
         members: Accounts.list_members(scope),
         prefill_subject: nil
       )
       |> load_teachings()}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:teachings}>
        <div id="teachings" class="space-y-4">
          <div class="flex flex-wrap items-end justify-between gap-3">
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
                  {Accounts.User.display_name(m.user)}
                </option>
              </select>
            </form>
            <p id="teachings-summary" class="text-sm text-base-content/70">
              {gettext("Grille %{level} :", level: @cg.level)}
              <span class="font-semibold text-base-content">
                {ngettext("%{count} matière", "%{count} matières", length(@assignments))} · {gettext(
                  "%{hours} h / semaine",
                  hours: Enum.sum_by(@assignments, & &1.weekly_hours)
                )}
              </span>
            </p>
          </div>

          <div
            :if={@unassigned != []}
            id="unassigned-subjects"
            role="status"
            class="rounded-[0.6rem] border border-error/40 bg-error/10 px-4 py-3 text-sm"
          >
            <p class="font-semibold text-error">
              {ngettext(
                "%{count} matière sans enseignant :",
                "%{count} matières sans enseignant :",
                length(@unassigned)
              )}
              <%= for {subject, i} <- Enum.with_index(@unassigned) do %>
                <span :if={i > 0}>, </span>
                <button
                  :if={@can_manage_assignments?}
                  type="button"
                  id={"prefill-#{subject.id}"}
                  phx-click="prefill_subject"
                  phx-value-subject={subject.name}
                  class="link"
                >
                  {subject.name}
                </button>
                <span :if={!@can_manage_assignments?}>{subject.name}</span>
              <% end %>
            </p>
            <p class="mt-1 text-base-content/70">
              {gettext(
                "Les notes et l'emploi du temps de ces matières restent bloqués tant qu'elles ne sont pas affectées."
              )}
            </p>
          </div>

          <div class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100">
            <table id="assignments" class="table">
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
                        <input
                          :for={s <- @roster_students}
                          type="hidden"
                          name="shown[]"
                          value={s.id}
                        />
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
                  <td>{Accounts.User.display_name(tc.teacher)}</td>
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
                          <option :for={m <- @members} value={m.user_id}>
                            {Accounts.User.display_name(m.user)}
                          </option>
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

          <p
            :if={@can_manage_assignments? and not @on_grid?}
            id="off-grid-hint"
            class="text-xs text-base-content/70"
          >
            {gettext(
              "Ce niveau n'est pas une colonne de la grille des coefficients : toutes les matières sont proposées."
            )}
            <.link navigate={~p"/school/settings/coefficients"} class="link link-primary">
              {gettext("Voir la grille")}
            </.link>
          </p>

          <form :if={@can_manage_assignments?} id="assign-form" phx-submit="assign" class="space-y-2">
            <div class="grid gap-2 sm:grid-cols-4">
              <select name="assignment[user_id]" class="select select-bordered select-sm">
                <option :for={m <- @members} value={m.user_id}>
                  {Accounts.User.display_name(m.user)}
                </option>
              </select>
              <select
                id="assign-subject"
                name="assignment[subject]"
                data-focus={JS.focus()}
                class="select select-bordered select-sm"
              >
                <option value="">{gettext("Choisir une matière")}</option>
                <option
                  :for={s <- @subject_options}
                  value={s.name}
                  selected={s.name == @prefill_subject}
                >
                  {s.name}
                </option>
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
      </.class_shell>
    </Layouts.app>
    """
  end

  defp load_teachings(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg
    assignments = Curriculum.list_assignments_for_class(scope, cg)

    socket
    |> assign(
      assignments: assignments,
      combinable_siblings:
        combinable_siblings_by_context(scope, assignments, socket.assigns.can_manage_assignments?),
      roster_students: Enrollment.list_students(scope, cg),
      exemptions:
        for(
          tc <- assignments,
          tc.catalog_subject.optional?,
          into: %{},
          do: {tc.id, Curriculum.exempt_student_ids(scope, tc)}
        )
    )
    |> assign(unassigned: Curriculum.unassigned_subjects_by_class(scope, [cg])[cg.id])
    |> ClassShell.assign_shell()
  end

  defp combinable_siblings_by_context(scope, assignments, true) do
    assignments
    |> Enum.reject(& &1.combined_course_id)
    |> Map.new(&{&1.id, Curriculum.combinable_siblings(scope, &1)})
  end

  defp combinable_siblings_by_context(_scope, _assignments, _admin?), do: %{}

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
          {:noreply, socket |> put_flash(:info, gettext("Teacher assigned.")) |> load_teachings()}

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
          {:noreply,
           socket |> put_flash(:info, gettext("Assignment removed.")) |> load_teachings()}

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
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_teachings()}
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
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_teachings()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_takers", %{"context-id" => cid} = params, socket) do
    takers = params |> Map.get("takers", []) |> Enum.reject(&(&1 == ""))

    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      shown = params |> Map.get("shown", []) |> Enum.reject(&(&1 == ""))

      case Curriculum.set_exemptions(socket.assigns.current_scope, tc, takers, shown) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Élèves concernés enregistrés."))
           |> load_teachings()}

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
      {:noreply, socket |> put_flash(:info, gettext("Teacher reassigned.")) |> load_teachings()}
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
           socket
           |> assign(cg: cg)
           |> ClassShell.assign_shell()
           |> put_flash(:info, gettext("Form master cleared."))}

        %{user_id: user_id} ->
          {:ok, cg} =
            Enrollment.set_form_master(socket.assigns.current_scope, socket.assigns.cg, user_id)

          {:noreply,
           socket
           |> assign(cg: cg)
           |> ClassShell.assign_shell()
           |> put_flash(:info, gettext("Form master assigned."))}

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
           |> load_teachings()}

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
       |> load_teachings()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("prefill_subject", %{"subject" => name}, socket) do
    {:noreply,
     socket
     |> assign(:prefill_subject, name)
     |> push_event("js-exec", %{to: "#assign-subject", attr: "data-focus"})}
  end

  defp parse_hours(v) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 and n <= 40 -> n
      _ -> 4
    end
  end

  defp class_coefficients_allowed?(scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.class_coefficients_allowed?
      _ -> false
    end
  end

  defp fmt_coef(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
end
