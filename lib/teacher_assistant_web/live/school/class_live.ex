defmodule TeacherAssistantWeb.School.ClassLive do
  @moduledoc """
  The class's Élèves tab (spec 2026-10-08 §4): the roster with its filters and
  per-student menu (open, transfer, withdraw), the « Inscrire un élève » drawer
  (a new student with their parent, or a former one re-enrolled) and the class's
  own « Gérer » menu (maximum size, delete).
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Drawer

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.{GuardianRelationship, Sex}
  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  @roster_filters [:all, :f, :m, :repeaters]

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
         can_manage_guardians?: Enrollment.can_manage_guardians?(scope),
         filter: :all,
         rq: "",
         drawer: nil
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
          <button
            id="enroll-button"
            type="button"
            class="btn btn-primary btn-sm gap-1.5"
            phx-click="open_enroll"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Inscrire un élève")}
          </button>
          <details :if={@can_manage_classes?} id="class-menu" class="dropdown dropdown-end">
            <summary class="btn btn-ghost btn-sm">{gettext("Gérer")} ▾</summary>
            <ul class="menu dropdown-content z-30 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 shadow-lg">
              <li>
                <button id="open-class-settings" type="button" phx-click="open_settings">
                  {gettext("Effectif maximum…")}
                </button>
              </li>
              <li>
                <button
                  id="delete-class"
                  type="button"
                  class="text-error"
                  phx-click="delete_class"
                  data-confirm={gettext("Supprimer la classe %{label} ?", label: @cg.label)}
                >
                  {gettext("Supprimer la classe")}
                </button>
              </li>
            </ul>
          </details>
        </:actions>

        <div
          :if={@roster != []}
          class="flex flex-wrap items-center gap-3 rounded-[0.6rem] border border-base-300 bg-base-100 px-3 py-2.5"
        >
          <form id="roster-search" phx-change="search_roster" class="min-w-48 flex-1">
            <label class="input input-sm w-full">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
              <input
                type="search"
                name="rq"
                value={@rq}
                phx-debounce="150"
                placeholder={gettext("Nom ou matricule")}
                aria-label={gettext("Rechercher dans la classe")}
              />
            </label>
          </form>
          <div id="roster-filter" role="group" aria-label={gettext("Filtre")} class="flex gap-1">
            <button
              :for={f <- roster_filters()}
              id={"roster-filter-#{f}"}
              type="button"
              phx-click="filter_roster"
              phx-value-filter={f}
              aria-pressed={to_string(@filter == f)}
              class={[
                "rounded-full px-3 py-1 text-sm font-semibold transition-colors",
                if(@filter == f,
                  do: "bg-primary/15 text-primary",
                  else: "text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              {filter_label(f)}
            </button>
          </div>
          <span id="roster-summary" class="ta-num text-xs text-base-content/70">
            {roster_summary(@roster)}
          </span>
        </div>

        <div
          :if={@roster != []}
          class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100"
        >
          <table id="class-roster" class="table">
            <thead>
              <tr>
                <th class="w-10">{gettext("N°")}</th>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Né(e) le")}</th>
                <th>{gettext("Parent principal")}</th>
                <th><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{row, n} <- Enum.with_index(visible_roster(@roster, @filter, @rq), 1)}
                id={"roster-row-#{row.enrollment.id}"}
                class="hover:bg-base-200/60"
              >
                <td class="ta-num text-base-content/60">{n}</td>
                <td>
                  <span class="flex items-center gap-3">
                    <.initials_avatar name={row.student.full_name} />
                    <span class="min-w-0">
                      <.link
                        navigate={~p"/school/students/#{row.student.id}"}
                        class="block font-semibold hover:text-primary"
                      >
                        {row.student.full_name}
                      </.link>
                      <span class="flex items-center gap-1.5 text-xs text-base-content/60">
                        {row.student.sex && Sex.label(row.student.sex)}
                        <span
                          :if={row.enrollment.repeater}
                          class="rounded bg-warning/20 px-1.5 text-[0.7rem] font-semibold text-warning"
                        >
                          {gettext("Redoublant")}
                        </span>
                      </span>
                    </span>
                  </span>
                </td>
                <td class="ta-num text-sm">{row.student.matricule}</td>
                <td class="ta-num text-sm">{format_date(row.student.birth_date)}</td>
                <td class="text-sm">
                  <%= if guardian = @guardians[row.student.id] do %>
                    <span class="block">{guardian.full_name}</span>
                    <span class="ta-num block text-xs text-base-content/60">{guardian.phone}</span>
                  <% else %>
                    <span class="text-xs font-semibold text-warning">{gettext("Aucun contact")}</span>
                  <% end %>
                </td>
                <td class="text-right">
                  <details id={"row-menu-#{row.enrollment.id}"} class="dropdown dropdown-end">
                    <summary class="btn btn-ghost btn-xs">{gettext("Gérer")} ▾</summary>
                    <ul class="menu dropdown-content z-30 mt-1 w-60 rounded-box border border-base-300 bg-base-100 p-1 text-left shadow-lg">
                      <li>
                        <.link navigate={~p"/school/students/#{row.student.id}"}>
                          {gettext("Ouvrir la fiche")}
                        </.link>
                      </li>
                      <li :if={@transfer_targets != []} class="menu-title text-xs">
                        {gettext("Transférer vers")}
                      </li>
                      <li :for={target <- @transfer_targets}>
                        <button
                          id={"transfer-#{row.enrollment.id}-#{target.id}"}
                          type="button"
                          phx-click="transfer"
                          phx-value-enrollment-id={row.enrollment.id}
                          phx-value-class-id={target.id}
                        >
                          {target.label}
                        </button>
                      </li>
                      <li>
                        <button
                          id={"withdraw-#{row.enrollment.id}"}
                          type="button"
                          class="text-error"
                          phx-click="withdraw"
                          phx-value-enrollment-id={row.enrollment.id}
                          data-confirm={gettext("Retirer cet élève de la classe ?")}
                        >
                          {gettext("Retirer de la classe…")}
                        </button>
                      </li>
                    </ul>
                  </details>
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
      </.class_shell>

      <.drawer
        :if={@drawer == :enroll}
        id="enroll-drawer"
        eyebrow={capacity_line(@shell.capacity)}
        title={gettext("Inscrire un élève")}
        on_close={JS.push("close_drawer")}
      >
        <.enroll_panel
          enroll_error={@enroll_error}
          enroll_mode={@enroll_mode}
          enroll={@enroll}
          can_manage_guardians?={@can_manage_guardians?}
          parent_matches={@parent_matches}
          q={@q}
          search_results={@search_results}
          year_id={@cg.academic_year_id}
        />
        <:footer :if={@enroll_mode == :new}>
          <span
            :if={@shell.capacity.max}
            id="enroll-after"
            class={[
              "ta-num mr-auto self-center text-xs",
              if(@shell.capacity.count + 1 > @shell.capacity.max,
                do: "font-semibold text-warning",
                else: "text-base-content/60"
              )
            ]}
          >
            {gettext("%{count} / %{max} élèves après cet ajout",
              count: @shell.capacity.count + 1,
              max: @shell.capacity.max
            )}
          </span>
          <button
            type="submit"
            form="enroll-form"
            name="then"
            value="another"
            id="enroll-another"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Inscrire et en ajouter un autre")}
          </button>
          <button type="submit" form="enroll-form" id="enroll-submit" class="btn btn-primary btn-sm">
            {gettext("Inscrire")}
          </button>
        </:footer>
      </.drawer>

      <.drawer
        :if={@drawer == :settings}
        id="class-settings-drawer"
        eyebrow={@cg.label}
        title={gettext("Effectif maximum")}
        on_close={JS.push("close_drawer")}
      >
        <form id="class-settings-form" phx-submit="save_settings" class="space-y-2">
          <label for="class-max-size" class="ta-eyebrow block">
            {gettext("Effectif maximum de la classe")}
          </label>
          <.input
            id="class-max-size"
            type="number"
            name="max_size"
            min="1"
            max="200"
            value={@cg.max_size}
            placeholder={school_max_placeholder(@current_scope)}
            class="input input-sm w-full"
          />
          <p class="text-xs text-base-content/60">
            {gettext(
              "Laissez vide pour suivre l'effectif de l'établissement. Alerte au-delà, sans bloquer."
            )}
          </p>
        </form>
        <:footer>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="close_drawer">
            {gettext("Annuler")}
          </button>
          <button type="submit" form="class-settings-form" class="btn btn-primary btn-sm">
            {gettext("Enregistrer")}
          </button>
        </:footer>
      </.drawer>
    </Layouts.app>
    """
  end

  attr :enroll_error, :string
  attr :enroll_mode, :atom, required: true
  attr :enroll, :map, required: true
  attr :can_manage_guardians?, :boolean, required: true
  attr :parent_matches, :list, required: true
  attr :q, :string, required: true
  attr :search_results, :list, required: true
  attr :year_id, :string, required: true

  defp enroll_panel(assigns) do
    ~H"""
    <div :if={@enroll_error} id="enroll-error" role="alert" class="alert alert-error alert-soft">
      <.icon name="hero-exclamation-triangle" class="size-5" />
      <span>{@enroll_error}</span>
    </div>

    <div role="group" aria-label={gettext("Type d'inscription")} class="grid grid-cols-2 gap-2">
      <button
        :for={{mode, label} <- [new: gettext("Nouvel élève"), existing: gettext("Ancien élève")]}
        id={"enroll-mode-#{mode}"}
        type="button"
        phx-click="enroll_mode"
        phx-value-mode={mode}
        aria-pressed={to_string(@enroll_mode == mode)}
        class={[
          "rounded-[0.5rem] border px-3 py-2 text-sm font-semibold transition-colors",
          if(@enroll_mode == mode,
            do: "border-primary bg-primary/10 text-primary",
            else: "border-base-300 text-base-content/80 hover:border-base-content/40"
          )
        ]}
      >
        {label}
      </button>
    </div>

    <form
      :if={@enroll_mode == :new}
      id="enroll-form"
      phx-change="enroll_change"
      phx-submit="enroll_new"
      class="space-y-4"
    >
      <div class="space-y-1">
        <label for="enroll-full-name" class="ta-eyebrow block">{gettext("Nom et prénoms")}</label>
        <.input
          id="enroll-full-name"
          type="text"
          name="enroll[full_name]"
          value={@enroll["full_name"]}
          placeholder={gettext("NOM Prénoms")}
          class="input input-sm w-full"
        />
      </div>
      <fieldset>
        <legend class="ta-eyebrow mb-2">{gettext("Sexe")}</legend>
        <div class="flex gap-2">
          <.chip_radio
            :for={sex <- [:f, :m]}
            id={"enroll-sex-#{sex}"}
            name="enroll[sex]"
            value={to_string(sex)}
            checked={@enroll["sex"] == to_string(sex)}
          >
            {Sex.label(sex)}
          </.chip_radio>
        </div>
      </fieldset>
      <div class="grid gap-3 sm:grid-cols-2">
        <div class="space-y-1">
          <label for="enroll-birth-date" class="ta-eyebrow block">
            {gettext("Date de naissance")}
          </label>
          <.input
            id="enroll-birth-date"
            type="date"
            name="enroll[birth_date]"
            value={@enroll["birth_date"]}
            class="input input-sm w-full"
          />
        </div>
        <div class="space-y-1">
          <label for="enroll-birth-place" class="ta-eyebrow block">
            {gettext("Lieu de naissance")}
          </label>
          <.input
            id="enroll-birth-place"
            type="text"
            name="enroll[birth_place]"
            value={@enroll["birth_place"]}
            class="input input-sm w-full"
          />
        </div>
      </div>
      <div class="space-y-1">
        <label for="enroll-matricule" class="ta-eyebrow block">
          {gettext("Matricule (facultatif)")}
        </label>
        <.input
          id="enroll-matricule"
          type="text"
          name="enroll[matricule]"
          value={@enroll["matricule"]}
          class="input input-sm w-full"
        />
      </div>
      <.input
        id="enroll-repeater"
        type="checkbox"
        name="enroll[repeater]"
        checked={@enroll["repeater"] == "true"}
        label={gettext("Redoublant dans ce niveau")}
      />

      <fieldset
        :if={@can_manage_guardians?}
        id="enroll-parent"
        class="space-y-3 rounded-[0.6rem] border border-base-300 p-3"
      >
        <legend class="ta-eyebrow px-1">{gettext("Parent ou tuteur · recommandé")}</legend>
        <.input
          id="enroll-parent-phone"
          type="tel"
          inputmode="tel"
          name="enroll[parent_phone]"
          value={@enroll["parent_phone"]}
          phx-debounce="300"
          placeholder={gettext("Téléphone : 6XX XX XX XX")}
          aria-label={gettext("Téléphone du parent")}
          class="input input-sm w-full"
        />
        <div :if={@parent_matches != []} id="enroll-parent-matches" class="space-y-2">
          <label
            :for={g <- @parent_matches}
            class="flex cursor-pointer items-start gap-2 rounded-[0.5rem] bg-primary/10 p-2 text-sm"
          >
            <input
              type="radio"
              name="enroll[parent_id]"
              value={g.id}
              checked={@enroll["parent_id"] == g.id or length(@parent_matches) == 1}
              class="radio radio-sm mt-0.5"
            />
            <span>
              {ngettext(
                "Déjà enregistré : %{name} (%{relationship} de %{count} élève)",
                "Déjà enregistré : %{name} (%{relationship} de %{count} élèves)",
                g.student_count,
                name: g.full_name,
                relationship: GuardianRelationship.label(g.relationship)
              )}
              <span class="block text-xs text-base-content/70">
                {gettext("Sera lié automatiquement.")}
              </span>
            </span>
          </label>
        </div>
        <div :if={@parent_matches == []} class="grid gap-2 sm:grid-cols-[1fr_auto]">
          <.input
            id="enroll-parent-name"
            type="text"
            name="enroll[parent_name]"
            value={@enroll["parent_name"]}
            placeholder={gettext("Nom du parent")}
            aria-label={gettext("Nom du parent")}
            class="input input-sm w-full"
          />
          <.input
            id="enroll-parent-relationship"
            type="select"
            name="enroll[parent_relationship]"
            value={@enroll["parent_relationship"]}
            options={Enum.map(GuardianRelationship.values(), &{GuardianRelationship.label(&1), &1})}
            aria-label={gettext("Lien")}
            class="select select-sm"
          />
        </div>
      </fieldset>
    </form>

    <div :if={@enroll_mode == :existing} class="space-y-3">
      <form id="enroll-search-form" phx-change="search">
        <.input
          type="search"
          id="enroll-search"
          name="q"
          value={@q}
          phx-debounce="300"
          placeholder={gettext("Nom ou matricule d'un ancien élève")}
          aria-label={gettext("Rechercher un ancien élève")}
          class="input input-sm w-full"
        />
      </form>
      <ul id="search-results" class="space-y-2">
        <li
          :for={student <- @search_results}
          class="flex items-center justify-between gap-3 rounded-[0.5rem] border border-base-300 px-3 py-2"
        >
          <span class="min-w-0 text-sm">
            <span class="block font-semibold">{student.full_name}</span>
            <span class="ta-num block text-xs text-base-content/60">
              {Enum.join(Enum.reject([student.matricule, last_class(student)], &is_nil/1), " · ")}
            </span>
          </span>
          <button
            :if={!enrolled_in?(student, @year_id)}
            id={"search-enroll-#{student.id}"}
            type="button"
            class="btn btn-primary btn-xs"
            phx-click="enroll_existing"
            phx-value-student-id={student.id}
          >
            {gettext("Réinscrire")}
          </button>
          <button
            :if={enrolled_in?(student, @year_id)}
            id={"search-enrolled-#{student.id}"}
            type="button"
            class="btn btn-xs"
            disabled
          >
            {gettext("Déjà inscrit cette année")}
          </button>
        </li>
      </ul>
      <p :if={@q != "" and @search_results == []} class="text-sm text-base-content/70">
        {gettext("Aucun élève trouvé.")}
      </p>
    </div>
    """
  end

  # --- Data -----------------------------------------------------------------------

  defp load_roster(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg
    roster = Enrollment.list_roster(scope, cg)

    # A transfer stays within the class's year: a past class has no targets.
    others =
      if cg.academic_year_id == scope.current_academic_year.id,
        do:
          Enrollment.list_class_groups(scope, scope.current_academic_year)
          |> Enum.reject(&(&1.id == cg.id)),
        else: []

    socket
    |> assign(
      roster: roster,
      guardians: Enrollment.primary_guardians(scope, Enum.map(roster, & &1.student.id)),
      # Same level first, then the rest by label.
      transfer_targets: Enum.sort_by(others, &{&1.level != cg.level, &1.label})
    )
    |> ClassShell.assign_shell(count: length(roster))
  end

  defp roster_filters, do: @roster_filters

  defp visible_roster(roster, filter, rq) do
    needle = rq |> String.trim() |> String.downcase()

    Enum.filter(roster, fn %{student: s, enrollment: e} ->
      keep? =
        case filter do
          :all -> true
          :repeaters -> e.repeater
          sex -> s.sex == sex
        end

      keep? and
        (needle == "" or String.contains?(String.downcase(s.full_name), needle) or
           String.contains?(String.downcase(s.matricule || ""), needle))
    end)
  end

  defp roster_summary(roster) do
    f = Enum.count(roster, &(&1.student.sex == :f))
    m = Enum.count(roster, &(&1.student.sex == :m))
    r = Enum.count(roster, & &1.enrollment.repeater)

    Enum.join(
      [
        gettext("%{count} F", count: f),
        gettext("%{count} G", count: m),
        ngettext("%{count} redoublant", "%{count} redoublants", r)
      ],
      " · "
    )
  end

  defp filter_label(:all), do: gettext("Tous")
  defp filter_label(:f), do: gettext("Filles")
  defp filter_label(:m), do: gettext("Garçons")
  defp filter_label(:repeaters), do: gettext("Redoublants")

  defp format_date(nil), do: ""
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp capacity_line(%{count: count, max: nil}),
    do: ngettext("%{count} élève", "%{count} élèves", count)

  defp capacity_line(%{count: count, max: max}), do: "#{count} / #{max}"

  defp school_max_placeholder(scope) do
    case Enrollment.school_max_size(scope) do
      nil -> nil
      n -> to_string(n)
    end
  end

  # --- Events: roster -------------------------------------------------------------

  def handle_event("search_roster", %{"rq" => rq}, socket),
    do: {:noreply, assign(socket, :rq, rq)}

  def handle_event("filter_roster", %{"filter" => f}, socket) do
    {:noreply, assign(socket, :filter, Enum.find(@roster_filters, :all, &(to_string(&1) == f)))}
  end

  def handle_event("transfer", %{"enrollment-id" => eid, "class-id" => cgid}, socket) do
    with %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         %{} = target <- Enum.find(socket.assigns.transfer_targets, &(&1.id == cgid)),
         {:ok, _} <- Enrollment.transfer(socket.assigns.current_scope, e, target) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Élève transféré en %{label}.", label: target.label))
       |> load_roster()}
    else
      {:error, :different_year} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("On ne transfère que vers une classe de la même année.")
         )}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("withdraw", %{"enrollment-id" => eid}, socket) do
    with %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         :ok <- Enrollment.withdraw(socket.assigns.current_scope, e) do
      {:noreply, socket |> put_flash(:info, gettext("Enrollment removed.")) |> load_roster()}
    else
      {:error, error} -> {:noreply, Authz.put_failure(socket, error)}
      nil -> {:noreply, socket}
    end
  end

  # --- Events: drawers ------------------------------------------------------------

  def handle_event("open_enroll", _params, socket) do
    {:noreply, socket |> assign(drawer: :enroll, enroll_mode: :new) |> reset_enroll()}
  end

  def handle_event("enroll_mode", %{"mode" => mode}, socket) do
    mode = if mode == "existing", do: :existing, else: :new
    {:noreply, assign(socket, enroll_mode: mode, enroll_error: nil)}
  end

  def handle_event("close_drawer", _params, socket), do: {:noreply, assign(socket, :drawer, nil)}

  def handle_event("enroll_change", %{"enroll" => params}, socket) do
    phone = params["parent_phone"] || ""

    matches =
      cond do
        not socket.assigns.can_manage_guardians? -> []
        phone == (socket.assigns.enroll["parent_phone"] || "") -> socket.assigns.parent_matches
        true -> Enrollment.find_guardians_by_phone(socket.assigns.current_scope, phone)
      end

    {:noreply, assign(socket, enroll: params, parent_matches: matches)}
  end

  def handle_event("enroll_new", %{"enroll" => params} = all, socket) do
    socket = assign(socket, :enroll, params)

    with {:ok, attrs} <- enroll_attrs(params, socket.assigns),
         {:ok, _} <- Enrollment.enroll_new(socket.assigns.current_scope, socket.assigns.cg, attrs) do
      socket = load_roster(socket)
      capacity = socket.assigns.shell.capacity

      # Spec KLM5: over the maximum is a warning, never a block.
      message =
        if capacity.over?,
          do:
            gettext("Élève inscrit. La classe dépasse l'effectif maximum (%{max}).",
              max: capacity.max
            ),
          else:
            gettext("Élève inscrit en %{label} (%{size}).",
              label: socket.assigns.cg.label,
              size: capacity_line(capacity)
            )

      socket = put_flash(socket, :info, message)

      if all["then"] == "another",
        do: {:noreply, reset_enroll(socket)},
        else: {:noreply, assign(socket, :drawer, nil)}
    else
      {:error, :duplicate_matricule} ->
        {:noreply,
         assign(
           socket,
           :enroll_error,
           gettext("This matricule already belongs to another student.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :enroll_error, message)}

      {:error, _} ->
        {:noreply, assign(socket, :enroll_error, gettext("Could not enroll the student."))}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     assign(socket,
       search_results: Enrollment.search_students(socket.assigns.current_scope, q),
       q: q
     )}
  end

  def handle_event("enroll_existing", %{"student-id" => sid}, socket) do
    with %{} = student <- Enum.find(socket.assigns.search_results, &(&1.id == sid)) do
      case Enrollment.enroll_existing(socket.assigns.current_scope, socket.assigns.cg, student) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Student re-enrolled."))
           |> assign(drawer: nil)
           |> load_roster()}

        {:error, :already_enrolled} ->
          {:noreply,
           assign(socket, :enroll_error, gettext("This student is already enrolled this year."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply, assign(socket, :enroll_error, gettext("Could not enroll the student."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # --- Events: the class ----------------------------------------------------------

  def handle_event("open_settings", _params, socket) when socket.assigns.can_manage_classes?,
    do: {:noreply, assign(socket, :drawer, :settings)}

  def handle_event("save_settings", %{"max_size" => raw}, socket)
      when socket.assigns.can_manage_classes? do
    with {:ok, value} <- parse_max_size(raw),
         {:ok, cg} <-
           Enrollment.set_class_max_size(socket.assigns.current_scope, socket.assigns.cg, value) do
      {:noreply,
       socket
       |> assign(cg: cg, drawer: nil)
       |> ClassShell.assign_shell(count: length(socket.assigns.roster))
       |> put_flash(:info, gettext("Effectif maximum enregistré."))}
    else
      :invalid ->
        {:noreply, put_flash(socket, :error, gettext("Entrez un nombre entre 1 et 200."))}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}
    end
  end

  def handle_event("delete_class", _params, socket) when socket.assigns.can_manage_classes? do
    case Enrollment.delete_class_group(socket.assigns.current_scope, socket.assigns.cg) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Class deleted."))
         |> push_navigate(to: ~p"/school/classes")}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :has_data} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This class has students or teachers — remove them first.")
         )}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}
    end
  end

  def handle_event(event, _params, socket)
      when event in ["open_settings", "save_settings", "delete_class"],
      do: {:noreply, socket}

  # Empty: follow the school's maximum.
  defp parse_max_size(raw), do: raw |> String.trim() |> max_size_value()

  defp max_size_value(""), do: {:ok, nil}

  defp max_size_value(text) do
    case Integer.parse(text) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _ -> :invalid
    end
  end

  # --- Enrolment ------------------------------------------------------------------

  defp reset_enroll(socket) do
    assign(socket,
      enroll: %{"sex" => "f", "parent_relationship" => "mere"},
      enroll_error: nil,
      parent_matches: [],
      search_results: [],
      q: ""
    )
  end

  # The form's params as `Enrollment.enroll_new/3` attributes, or a message.
  defp enroll_attrs(params, assigns) do
    name = String.trim(params["full_name"] || "")

    with :ok <- required_name(name),
         {:ok, birth_date} <- parse_birth_date(params["birth_date"]),
         {:ok, guardian} <- guardian_attrs(params, assigns) do
      {:ok,
       %{
         full_name: name,
         sex: if(params["sex"] == "m", do: :m, else: :f),
         birth_date: birth_date,
         birth_place: presence(params["birth_place"]),
         matricule: presence(params["matricule"]),
         repeater: params["repeater"] == "true",
         guardian: guardian
       }}
    end
  end

  defp required_name(""), do: {:error, gettext("Le nom de l'élève est obligatoire.")}
  defp required_name(_name), do: :ok

  defp parse_birth_date(value) when value in [nil, ""], do: {:ok, nil}

  defp parse_birth_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, gettext("Date de naissance invalide.")}
    end
  end

  defp guardian_attrs(_params, %{can_manage_guardians?: false}), do: {:ok, nil}

  defp guardian_attrs(params, %{parent_matches: matches}) do
    phone = String.trim(params["parent_phone"] || "")
    name = String.trim(params["parent_name"] || "")
    picked = Enum.find(matches, &(&1.id == params["parent_id"])) || single(matches)

    cond do
      picked ->
        {:ok, %{guardian_id: picked.id}}

      matches != [] ->
        {:error, gettext("Choisissez le parent parmi ceux déjà enregistrés.")}

      phone == "" and name == "" ->
        {:ok, nil}

      not TeacherAssistant.Academics.Guardian.Phone.valid?(phone) ->
        {:error, gettext("Numéro de téléphone du parent invalide.")}

      name == "" ->
        {:error, gettext("Indiquez le nom du parent.")}

      true ->
        {:ok,
         %{
           full_name: name,
           phone: phone,
           relationship: relationship(params["parent_relationship"])
         }}
    end
  end

  # « 6ème A · 2024-2025 », the student's most recent class.
  defp last_class(%{enrollments: []}), do: nil

  defp last_class(%{enrollments: enrollments}) do
    e = Enum.max_by(enrollments, & &1.academic_year.start_date, Date)
    "#{e.class_group.label} · #{e.academic_year.name}"
  end

  defp enrolled_in?(%{enrollments: enrollments}, year_id),
    do: Enum.any?(enrollments, &(&1.academic_year_id == year_id))

  defp single([one]), do: one
  defp single(_), do: nil

  defp relationship(value),
    do: Enum.find(GuardianRelationship.values(), :autre, &(to_string(&1) == value))

  defp presence(nil), do: nil

  defp presence(v) do
    case String.trim(v) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
