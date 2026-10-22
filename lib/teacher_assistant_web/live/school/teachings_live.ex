defmodule TeacherAssistantWeb.School.TeachingsLive do
  @moduledoc """
  The class's Enseignements tab (spec 2026-10-08 §5): form master, then one row per
  subject of the class — its teacher, hours, coefficient, combined course — and
  the subjects the grid expects that still have no teacher. A row opens a drawer
  to edit the assignment (teacher, hours, coefficient, takers), teach it together
  with other classes, or remove it; « Affecter une matière » opens the add drawer.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Curriculum, Enrollment}
  alias TeacherAssistantWeb.Numbers
  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]
  import TeacherAssistantWeb.Drawer

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
         prefill_subject: nil,
         adding?: false,
         editing_id: nil
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
        <:actions :if={@can_manage_assignments?}>
          <button id="open-assign" type="button" class="btn btn-primary" phx-click="open_assign">
            <.icon name="hero-plus" class="size-4" />
            {gettext("Affecter une matière")}
          </button>
        </:actions>

        <div id="teachings" class="space-y-5">
          <div
            :if={@unassigned != []}
            id="unassigned-subjects"
            role="status"
            class="flex gap-3 rounded-box border border-error/40 bg-error/10 px-4 py-3 text-sm"
          >
            <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0 text-error" />
            <div class="min-w-0">
              <p>
                <span class="font-semibold text-error">
                  {ngettext(
                    "%{count} matière sans enseignant :",
                    "%{count} matières sans enseignant :",
                    length(@unassigned)
                  )}
                </span>
                {Enum.map_join(@unassigned, ", ", & &1.name)}
              </p>
              <p class="mt-0.5 text-base-content/70">
                {gettext(
                  "Les notes et l'emploi du temps de ces matières restent bloqués tant qu'elles ne sont pas affectées."
                )}
              </p>
            </div>
          </div>

          <form
            :if={@can_manage_classes?}
            id="form-master-form"
            phx-change="set_form_master"
            class="ta-section"
          >
            <.settings_row
              label={gettext("Professeur principal")}
              for="form-master-select"
              help={gettext("Suit la classe et prépare le conseil de classe.")}
              class="!border-t-0"
            >
              <.input
                type="select"
                id="form-master-select"
                name="user_id"
                value={@cg.form_master_user_id}
                prompt={gettext("Aucun")}
                options={member_options(@members)}
              />
            </.settings_row>
          </form>

          <section :if={@rows != []} id="assignments" class="ta-section">
            <header class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 px-4 pb-2 pt-4 sm:px-5">
              <h2 class="text-base font-semibold">{gettext("Matières")}</h2>
              <p id="teachings-summary" class="text-sm text-base-content/70">
                {gettext("Grille %{level} :", level: @cg.level)}
                {ngettext("%{count} matière", "%{count} matières", length(@assignments))} · {gettext(
                  "%{hours} h / semaine",
                  hours: Enum.sum_by(@assignments, &(&1.weekly_hours || 0))
                )}
              </p>
            </header>
            <div>
              <%= for row <- @rows do %>
                <.list_row
                  :if={match?({:assigned, _}, row)}
                  id={"assignment-row-#{elem(row, 1).id}"}
                  phx-click={@can_manage_assignments? && "edit_teaching"}
                  phx-value-id={elem(row, 1).id}
                  title={elem(row, 1).subject}
                  meta={Accounts.User.display_name(elem(row, 1).teacher)}
                  selected={@editing_id == elem(row, 1).id}
                >
                  <.teaching_details
                    tc={elem(row, 1)}
                    partners={Map.get(@partners, elem(row, 1).id, [])}
                    roster_size={length(@roster_students)}
                    exempt={Map.get(@exemptions, elem(row, 1).id)}
                  />
                </.list_row>
                <.list_row
                  :if={match?({:missing, _}, row)}
                  id={"prefill-#{elem(row, 1).id}"}
                  phx-click={@can_manage_assignments? && "prefill_subject"}
                  phx-value-subject={elem(row, 1).name}
                  title={elem(row, 1).name}
                  meta={gettext("Sans enseignant")}
                  meta_class="font-medium text-error"
                />
              <% end %>
            </div>
          </section>

          <.empty_state
            :if={@rows == []}
            icon="hero-academic-cap"
            title={gettext("Aucun enseignant affecté")}
          />

          <p
            :if={@can_manage_assignments? and not @on_grid?}
            id="off-grid-hint"
            class="text-sm text-base-content/70"
          >
            {gettext(
              "Ce niveau n'est pas une colonne de la grille des coefficients : toutes les matières sont proposées."
            )}
            <.link navigate={~p"/school/settings/coefficients"} class="link link-primary">
              {gettext("Voir la grille")}
            </.link>
          </p>
        </div>

        <.drawer
          :if={@adding? and @can_manage_assignments?}
          id="assign-drawer"
          eyebrow={@cg.label}
          title={gettext("Affecter une matière")}
          on_close={JS.push("close_assign")}
        >
          <form id="assign-form" phx-submit="assign" class="space-y-1">
            <.input
              type="select"
              id="assign-subject"
              name="assignment[subject]"
              label={gettext("Matière")}
              value={@prefill_subject}
              prompt={gettext("Choisir une matière")}
              options={Enum.map(@subject_options, & &1.name)}
            />
            <.input
              type="select"
              id="assign-teacher"
              name="assignment[user_id]"
              label={gettext("Enseignant")}
              value={nil}
              options={member_options(@members)}
            />
            <.input
              type="number"
              id="assign-hours"
              name="assignment[weekly_hours]"
              label={gettext("Heures par semaine")}
              value="4"
              min="1"
              max="40"
            />
          </form>
          <:footer>
            <button type="button" class="btn btn-ghost" phx-click="close_assign">
              {gettext("Annuler")}
            </button>
            <button type="submit" form="assign-form" class="btn btn-primary">
              {gettext("Affecter")}
            </button>
          </:footer>
        </.drawer>

        <.teaching_drawer
          :if={@editing}
          tc={@editing}
          members={@members}
          partners={Map.get(@partners, @editing.id, [])}
          siblings={Map.get(@combinable_siblings, @editing.id, [])}
          roster_students={@roster_students}
          exempt={Map.get(@exemptions, @editing.id)}
          class_coefficients_allowed?={@class_coefficients_allowed?}
        />
      </.class_shell>
    </Layouts.app>
    """
  end

  attr :tc, :map, required: true
  attr :partners, :list, required: true
  attr :roster_size, :integer, required: true

  attr :exempt, :any,
    default: nil,
    doc: "the exempt student ids (a MapSet) of an optional subject"

  # The row's second line: hours, coefficient and the flags that matter.
  defp teaching_details(assigns) do
    ~H"""
    <span class="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-base-content/70">
      <span>
        {gettext("%{hours} h / sem.", hours: @tc.weekly_hours)} · {gettext("coef. %{c}",
          c: Numbers.decimal(@tc.effective_coefficient, trim: true)
        )}
        <span :if={@tc.coefficient} class="text-xs">({gettext("propre à la classe")})</span>
      </span>
      <span
        :if={@partners != []}
        id={"combined-#{@tc.id}"}
        class="badge badge-sm badge-ghost"
      >
        {gettext("avec %{classes}", classes: Enum.join(@partners, ", "))}
      </span>
      <span :if={@exempt} id={"takers-#{@tc.id}"} class="badge badge-sm badge-ghost">
        {gettext("Option")} ·
        <span class="ta-num">{@roster_size - MapSet.size(@exempt)}/{@roster_size}</span>
      </span>
      <span :if={!@tc.taught_here?} id={"not-taught-#{@tc.id}"} class="badge badge-sm badge-warning">
        {gettext("Non enseignée à ce niveau selon la grille")}
      </span>
    </span>
    """
  end

  attr :tc, :map, required: true
  attr :members, :list, required: true
  attr :partners, :list, required: true
  attr :siblings, :list, required: true
  attr :roster_students, :list, required: true
  attr :exempt, :any, default: nil
  attr :class_coefficients_allowed?, :boolean, required: true

  defp teaching_drawer(assigns) do
    ~H"""
    <.drawer
      id="teaching-drawer"
      eyebrow={gettext("Enseignement")}
      title={@tc.subject}
      on_close={JS.push("close_teaching")}
    >
      <form id={"teaching-form-#{@tc.id}"} phx-submit="save_teaching" class="space-y-1">
        <input type="hidden" name="context-id" value={@tc.id} />
        <.input
          type="select"
          id="teaching-teacher"
          name="teaching[user_id]"
          label={gettext("Enseignant")}
          value={@tc.teacher_user_id}
          options={member_options(@members, @tc.teacher)}
        />

        <.input
          :if={!@tc.combined_course_id}
          type="number"
          id="teaching-hours"
          name="teaching[weekly_hours]"
          label={gettext("Heures par semaine")}
          value={@tc.weekly_hours}
          min="1"
          max="40"
        />
        <div :if={@tc.combined_course_id} class="fieldset">
          <span class="label mb-1">{gettext("Heures par semaine")}</span>
          <p class="ta-num text-base">{@tc.weekly_hours}</p>
          <p class="text-xs text-base-content/70">
            {gettext("Communes aux classes regroupées : séparez-les pour les changer.")}
          </p>
        </div>

        <div :if={@class_coefficients_allowed?} id={"coefficient-#{@tc.id}"}>
          <.input
            id="teaching-coefficient"
            name="teaching[coefficient]"
            label={gettext("Coefficient")}
            value={Numbers.decimal(@tc.effective_coefficient, trim: true)}
            inputmode="decimal"
            class={if @tc.coefficient, do: "w-full input border-warning", else: "w-full input"}
          />
          <div class="-mt-1 flex flex-wrap items-center gap-x-2 text-xs text-base-content/70">
            <span :if={!@tc.coefficient}>{gettext("Valeur de la grille des coefficients.")}</span>
            <span :if={@tc.coefficient && @tc.grid_coefficient}>
              {gettext("Propre à la classe — modèle : %{value}",
                value: Numbers.decimal(@tc.grid_coefficient.coefficient, trim: true)
              )}
            </span>
            <button
              :if={@tc.coefficient}
              id={"reset-coefficient-#{@tc.id}"}
              type="button"
              class="btn btn-ghost btn-sm px-1"
              phx-click="reset_coefficient"
              data-confirm={gettext("Revenir au coefficient du modèle ?")}
              phx-value-context-id={@tc.id}
            >
              {gettext("Revenir au modèle")}
            </button>
          </div>
        </div>
        <div :if={!@class_coefficients_allowed?} class="fieldset">
          <span class="label mb-1">{gettext("Coefficient")}</span>
          <p class="ta-num text-base">{Numbers.decimal(@tc.effective_coefficient, trim: true)}</p>
          <p class="text-xs text-base-content/70">
            {gettext("Les coefficients propres à une classe sont désactivés.")}
          </p>
        </div>

        <fieldset :if={@exempt} id={"takers-form-#{@tc.id}"} class="space-y-1 pt-3">
          <legend class="text-sm font-semibold">
            {gettext("Élèves concernés")}
            <span class="ta-num font-normal text-base-content/70">
              ({length(@roster_students) - MapSet.size(@exempt)}/{length(@roster_students)})
            </span>
          </legend>
          <input type="hidden" name="takers[]" value="" />
          <input :for={s <- @roster_students} type="hidden" name="shown[]" value={s.id} />
          <label
            :for={s <- @roster_students}
            class="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg px-1 hover:bg-base-200"
          >
            <input
              type="checkbox"
              name="takers[]"
              value={s.id}
              checked={not MapSet.member?(@exempt, s.id)}
              class="checkbox checkbox-sm"
            />
            <span class="truncate">{s.full_name}</span>
          </label>
        </fieldset>
      </form>

      <section id={"combine-section-#{@tc.id}"} class="space-y-2 border-t border-base-300 pt-4">
        <h3 class="text-sm font-semibold">{gettext("Enseigner ensemble")}</h3>
        <%= cond do %>
          <% @tc.combined_course_id -> %>
            <p class="text-sm text-base-content/70">
              {gettext("Cours commun : %{label}", label: @tc.combined_course.label)}
            </p>
            <button
              id={"split-#{@tc.id}"}
              type="button"
              class="btn btn-outline"
              phx-click="split_course"
              phx-value-context-id={@tc.id}
              data-confirm={gettext("Séparer cet enseignement combiné ?")}
            >
              {gettext("Séparer les classes")}
            </button>
          <% @siblings != [] -> %>
            <p class="text-sm text-base-content/70">
              {gettext("Un seul cours pour plusieurs classes, avec le même enseignant.")}
            </p>
            <form id={"teach-together-#{@tc.id}"} phx-submit="teach_together" class="space-y-2">
              <input type="hidden" name="context-id" value={@tc.id} />
              <div class="flex flex-wrap gap-2">
                <label
                  :for={sib <- @siblings}
                  class="flex min-h-11 cursor-pointer items-center gap-2 rounded-full border border-base-300 px-3 has-[:checked]:border-primary has-[:checked]:bg-primary/10"
                >
                  <input
                    type="checkbox"
                    name="sibling-ids[]"
                    value={sib.id}
                    class="checkbox checkbox-sm"
                  />
                  {sib.class_group.label}
                </label>
              </div>
              <button type="submit" class="btn btn-outline">
                {gettext("Enseigner ensemble")}
              </button>
            </form>
          <% true -> %>
            <p class="text-sm text-base-content/70">
              {gettext("Aucune autre classe n'a cette matière avec le même enseignant.")}
            </p>
        <% end %>
      </section>

      <section class="space-y-2 border-t border-base-300 pt-4">
        <p class="text-sm text-base-content/70">
          {gettext(
            "Une affectation qui a déjà des notes ou une progression ne peut pas être retirée."
          )}
        </p>
        <button
          id={"unassign-#{@tc.id}"}
          type="button"
          class="btn btn-ghost text-error"
          phx-click="unassign"
          phx-value-context-id={@tc.id}
          data-confirm={gettext("Retirer cette affectation ?")}
        >
          {gettext("Retirer l'affectation")}
        </button>
      </section>

      <:footer>
        <button type="button" class="btn btn-ghost" phx-click="close_teaching">
          {gettext("Fermer")}
        </button>
        <button type="submit" form={"teaching-form-#{@tc.id}"} class="btn btn-primary">
          {gettext("Enregistrer")}
        </button>
      </:footer>
    </.drawer>
    """
  end

  defp load_teachings(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg
    assignments = Curriculum.list_assignments_for_class(scope, cg)
    students = Enrollment.list_students(scope, cg)
    unassigned = Curriculum.unassigned_subjects_by_class(scope, [cg])[cg.id]

    socket
    |> assign(
      assignments: assignments,
      rows: rows(assignments, unassigned),
      partners: partners_by_context(scope, cg, assignments),
      combinable_siblings:
        combinable_siblings_by_context(scope, assignments, socket.assigns.can_manage_assignments?),
      roster_students: students,
      unassigned: unassigned,
      exemptions:
        for(
          tc <- assignments,
          tc.catalog_subject.optional?,
          into: %{},
          do: {tc.id, Curriculum.exempt_student_ids(scope, tc)}
        )
    )
    |> assign_editing()
    |> ClassShell.assign_shell(count: length(students), unassigned: unassigned)
  end

  # The drawer's assignment, re-read from the freshly loaded list (nil once removed).
  defp assign_editing(socket) do
    editing = Enum.find(socket.assigns.assignments, &(&1.id == socket.assigns.editing_id))
    assign(socket, editing: editing, editing_id: editing && editing.id)
  end

  # The class's assignments and the subjects the grid expects without one, by name.
  defp rows(assignments, unassigned) do
    (Enum.map(assignments, &{:assigned, &1}) ++ Enum.map(unassigned, &{:missing, &1}))
    |> Enum.sort_by(fn
      {:assigned, tc} -> String.downcase(tc.subject)
      {:missing, subject} -> String.downcase(subject.name)
    end)
  end

  # Per combined assignment, the labels of the other classes taught with this one.
  defp partners_by_context(scope, cg, assignments) do
    for %{combined_course_id: course_id} = tc <- assignments, course_id != nil, into: %{} do
      labels =
        course_id
        |> Curriculum.contexts_of_course!(scope: scope)
        # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
        |> Ash.load!(:class_group, scope: scope)
        |> Enum.reject(&(&1.class_group_id == cg.id))
        |> Enum.map(& &1.class_group.label)
        |> Enum.sort()

      {tc.id, labels}
    end
  end

  defp combinable_siblings_by_context(scope, assignments, true) do
    assignments
    |> Enum.reject(& &1.combined_course_id)
    |> Map.new(&{&1.id, Curriculum.combinable_siblings(scope, &1)})
  end

  defp combinable_siblings_by_context(_scope, _assignments, _admin?), do: %{}

  def handle_event("open_assign", _params, socket),
    do: {:noreply, assign(socket, adding?: true, editing_id: nil, editing: nil)}

  def handle_event("close_assign", _params, socket),
    do: {:noreply, assign(socket, adding?: false, prefill_subject: nil)}

  def handle_event(
        "edit_teaching",
        %{"id" => id},
        %{assigns: %{can_manage_assignments?: true}} = socket
      ) do
    {:noreply, socket |> assign(editing_id: id, adding?: false) |> assign_editing()}
  end

  def handle_event("edit_teaching", _params, socket), do: {:noreply, socket}

  def handle_event("close_teaching", _params, socket),
    do: {:noreply, assign(socket, editing_id: nil, editing: nil)}

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
          {:noreply,
           socket
           |> put_flash(:info, gettext("Teacher assigned."))
           |> assign(adding?: false, prefill_subject: nil)
           |> load_teachings()}

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
    with %{} = tc <- find_assignment(socket, cid) do
      case Curriculum.remove_assignment(socket.assigns.current_scope, tc) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Assignment removed."))
           |> assign(editing_id: nil)
           |> load_teachings()}

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

  # The drawer's one save: teacher and weekly hours, the class coefficient and, for
  # an optional subject, the students who take it. Only what changed is written.
  def handle_event("save_teaching", %{"context-id" => cid} = params, socket) do
    attrs = Map.get(params, "teaching", %{})

    with %{} = tc <- find_assignment(socket, cid),
         :ok <- save_teacher_and_hours(socket, tc, attrs),
         :ok <- save_coefficient(socket, tc, attrs["coefficient"]),
         :ok <- save_takers(socket, tc, params) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Enseignement enregistré."))
       |> assign(editing_id: nil)
       |> load_teachings()}
    else
      nil -> {:noreply, socket}
      {:error, reason} -> {:noreply, socket |> put_save_error(reason) |> load_teachings()}
    end
  end

  def handle_event("reset_coefficient", %{"context-id" => cid}, socket) do
    with %{} = tc <- find_assignment(socket, cid),
         {:ok, _} <- Curriculum.clear_assignment_coefficient(socket.assigns.current_scope, tc) do
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_teachings()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_form_master", %{"user_id" => uid}, socket) do
    with true <- socket.assigns.can_manage_classes?,
         {:ok, user_id, message} <- form_master_target(uid, socket.assigns.members),
         {:ok, cg} <-
           Enrollment.set_form_master(socket.assigns.current_scope, socket.assigns.cg, user_id) do
      {:noreply,
       socket
       |> assign(cg: cg)
       |> ClassShell.assign_shell(
         count: length(socket.assigns.roster_students),
         unassigned: socket.assigns.unassigned
       )
       |> put_flash(:info, message)}
    else
      {:error, error} -> {:noreply, Authz.put_failure(socket, error)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("teach_together", %{"context-id" => cid} = params, socket) do
    with %{} = tc <- find_assignment(socket, cid) do
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
    with %{} = tc <- find_assignment(socket, cid),
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
     assign(socket, prefill_subject: name, adding?: true, editing_id: nil, editing: nil)}
  end

  defp find_assignment(socket, cid), do: Enum.find(socket.assigns.assignments, &(&1.id == cid))

  # A combined course keeps its hours (shared by its classes): only its teacher
  # changes, as before. Otherwise teacher and hours go through `place_assignment/5`.
  defp save_teacher_and_hours(socket, %{combined_course_id: course_id} = tc, attrs)
       when not is_nil(course_id) do
    uid = attrs["user_id"] || tc.teacher_user_id

    with false <- uid == tc.teacher_user_id,
         %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == uid)),
         {:ok, _} <- Curriculum.reassign_teacher(socket.assigns.current_scope, tc, member.user) do
      :ok
    else
      true -> :ok
      nil -> {:error, :not_assignable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_teacher_and_hours(socket, tc, attrs) do
    uid = attrs["user_id"] || tc.teacher_user_id
    hours = String.trim(attrs["weekly_hours"] || to_string(tc.weekly_hours))

    if uid == tc.teacher_user_id and hours == to_string(tc.weekly_hours) do
      :ok
    else
      socket.assigns.current_scope
      |> Curriculum.place_assignment(socket.assigns.cg, tc.catalog_subject, uid, hours)
      |> ok()
    end
  end

  # An empty field, or the value already in force, writes nothing.
  defp save_coefficient(socket, tc, value) when is_binary(value) do
    case Curriculum.parse_coefficient(value) do
      {:ok, dec} ->
        if Decimal.equal?(dec, tc.effective_coefficient),
          do: :ok,
          else:
            socket.assigns.current_scope
            |> Curriculum.set_assignment_coefficient(tc, value)
            |> ok()

      :error ->
        if String.trim(value) == "", do: :ok, else: {:error, :invalid_coefficient}
    end
  end

  defp save_coefficient(_socket, _tc, _value), do: :ok

  defp save_takers(socket, tc, %{"shown" => shown} = params) do
    if Map.has_key?(socket.assigns.exemptions, tc.id) do
      takers = params |> Map.get("takers", []) |> Enum.reject(&(&1 == ""))
      shown = Enum.reject(shown, &(&1 == ""))
      Curriculum.set_exemptions(socket.assigns.current_scope, tc, takers, shown)
    else
      :ok
    end
  end

  defp save_takers(_socket, _tc, _params), do: :ok

  defp ok({:ok, _}), do: :ok
  defp ok(:ok), do: :ok
  defp ok({:error, _} = error), do: error

  defp put_save_error(socket, %Ash.Error.Forbidden{}), do: Authz.put_not_allowed(socket)

  defp put_save_error(socket, :invalid_hours),
    do: put_flash(socket, :error, gettext("Saisissez un nombre d'heures entre 1 et 40."))

  defp put_save_error(socket, :not_assignable),
    do: put_flash(socket, :error, gettext("This member cannot be assigned."))

  defp put_save_error(socket, :invalid_coefficient),
    do: put_flash(socket, :error, gettext("Enter a positive coefficient."))

  defp put_save_error(socket, :class_coefficients_disabled),
    do:
      put_flash(
        socket,
        :error,
        gettext("Les coefficients propres à une classe sont désactivés.")
      )

  defp put_save_error(socket, :combined),
    do:
      put_flash(
        socket,
        :error,
        gettext("Séparez l'enseignement combiné pour changer ses heures.")
      )

  defp put_save_error(socket, error), do: Authz.put_failure(socket, error)

  # Members as select options; `current` (the assignment's teacher) is kept first
  # when they are no longer an active member, so saving never swaps them silently.
  defp member_options(members, current \\ nil) do
    options = Enum.map(members, &{Accounts.User.display_name(&1.user), &1.user_id})

    if current && not Enum.any?(members, &(&1.user_id == current.id)),
      do: [{Accounts.User.display_name(current), current.id} | options],
      else: options
  end

  # The chosen form master (nil clears it) and the flash, or :unknown for a stale id.
  defp form_master_target("", _members), do: {:ok, nil, gettext("Form master cleared.")}

  defp form_master_target(uid, members) do
    case Enum.find(members, &(&1.user_id == uid)) do
      %{user_id: user_id} -> {:ok, user_id, gettext("Form master assigned.")}
      nil -> :unknown
    end
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
end
