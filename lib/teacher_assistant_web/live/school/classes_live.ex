defmodule TeacherAssistantWeb.School.ClassesLive do
  @moduledoc """
  The school's classes (spec 2026-10-08 §2, UX refonte 2026-11-03 « Classes »): a
  table grouped by level (a list on phones), filter pills (Toutes, Sans PP,
  Matières à affecter) and a text filter, the « Mode désignation » that sets
  every class's form master in one save, and the « Nouvelle classe » drawer that
  builds the label from level, série and suffix.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Drawer

  alias TeacherAssistant.{Accounts, Curriculum, Enrollment}
  alias TeacherAssistant.Academics.{ClassGroup, SchoolTemplates}
  alias TeacherAssistant.Accounts.User

  @filters [:all, :no_pp, :to_assign]
  @other_level "__other__"

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace == nil do
      {:ok, push_navigate(socket, to: ~p"/school")}
    else
      profile =
        case Accounts.fetch_school_profile(scope) do
          {:ok, p} -> p
          _ -> nil
        end

      {:ok,
       socket
       |> assign(
         page_title: gettext("Classes"),
         profile: profile,
         can_manage_classes?: Enrollment.can_manage_classes?(scope),
         filters: @filters,
         filter: :all,
         mode: nil,
         q: "",
         members: [],
         pp_draft: %{},
         pp_changes: 0,
         drawer?: false
       )
       |> load_classes()}
    end
  end

  def handle_params(params, _uri, socket) do
    filter = Enum.find(@filters, :all, &(to_string(&1) == params["f"]))

    mode =
      if params["mode"] == "designate" and socket.assigns.can_manage_classes? and
           socket.assigns.classes != [],
         do: :designate

    {:noreply,
     socket
     |> assign(filter: filter, mode: mode)
     |> assign_draft()}
  end

  # « Mode désignation »: the members to choose from and a draft PP per class.
  defp assign_draft(%{assigns: %{mode: :designate}} = socket) do
    members =
      case socket.assigns.members do
        [] -> Accounts.list_members(socket.assigns.current_scope)
        members -> members
      end

    draft = Map.new(socket.assigns.classes, &{&1.cg.id, &1.cg.form_master_user_id || ""})
    assign(socket, members: members, pp_draft: draft, pp_changes: 0)
  end

  defp assign_draft(socket), do: assign(socket, pp_draft: %{}, pp_changes: 0)

  defp pp_changes(classes, draft) do
    for %{cg: cg} <- classes,
        Map.has_key?(draft, cg.id),
        draft[cg.id] != (cg.form_master_user_id || ""),
        do: {cg, if(draft[cg.id] == "", do: nil, else: draft[cg.id])}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-classes" class="space-y-6">
        <.page_header
          eyebrow={gettext("Établissement")}
          title={gettext("Classes")}
          subtitle={@year && header_subtitle(@classes)}
        >
          <:actions>
            <.link
              :if={@year && @can_manage_classes? && @classes != [] && @mode != :designate}
              id="designate-button"
              patch={classes_path(@filter, :designate)}
              class="btn btn-outline btn-sm gap-1.5"
            >
              <.icon name="hero-user-plus" class="size-4" /> {gettext("Désigner les PP")}
            </.link>
            <button
              :if={@year && @can_manage_classes?}
              id="new-class-button"
              type="button"
              class="btn btn-outline btn-sm gap-1.5"
              phx-click="open_drawer"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Nouvelle classe")}
            </button>
          </:actions>
        </.page_header>

        <%= if @year == nil do %>
          <.setup_gate
            icon="hero-rectangle-group"
            eyebrow={gettext("Get started")}
            title={gettext("No active academic year")}
            message={
              if @can_manage_classes?,
                do: gettext("Set up an academic year before creating classes."),
                else: gettext("L'année scolaire n'a pas encore été créée.")
            }
          >
            <:action>
              <.link
                :if={@can_manage_classes?}
                navigate={~p"/school/settings"}
                class="btn btn-primary"
              >
                {gettext("Go to settings")}
              </.link>
            </:action>
          </.setup_gate>
        <% else %>
          <div :if={@classes != []} class="flex flex-col gap-3 sm:flex-row sm:items-center">
            <.filter_pills id="class-filters" class="sm:flex-none">
              <:pill
                :for={f <- @filters}
                id={"filter-#{f}"}
                patch={classes_path(f, @mode)}
                count={@counts[f]}
                current={f == @filter}
              >
                {filter_label(f)}
              </:pill>
            </.filter_pills>
            <form id="class-filter" phx-change="filter_text" class="min-w-48 flex-1">
              <label class="input w-full">
                <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                <input
                  type="search"
                  name="q"
                  value={@q}
                  phx-debounce="150"
                  placeholder={gettext("Classe ou filière (ESF, 2nde…)")}
                  aria-label={gettext("Rechercher une classe")}
                />
              </label>
            </form>
          </div>

          <form
            :if={@classes != []}
            id="designate-form"
            phx-change="draft_pp"
            phx-submit="save_pps"
            class="space-y-5"
          >
            <div
              :if={@mode == :designate}
              id="designate-banner"
              class="flex flex-wrap items-center gap-3 rounded-box border border-warning/40 bg-warning/10 px-4 py-3 text-sm"
            >
              <span class="min-w-56 flex-1">
                {gettext(
                  "Mode désignation : choisissez un professeur principal par classe, puis enregistrez tout d'un coup."
                )}
              </span>
              <.link patch={classes_path(@filter, nil)} class="btn btn-ghost btn-sm">
                {gettext("Annuler")}
              </.link>
              <button
                id="save-pps"
                type="submit"
                class="btn btn-primary btn-sm"
                disabled={@pp_changes == 0}
                phx-disable-with={gettext("Enregistrement…")}
              >
                {ngettext("Enregistrer · %{count} PP", "Enregistrer · %{count} PP", @pp_changes)}
              </button>
            </div>

            <.level_group
              :for={{level, rows} <- visible_groups(@classes, @filter, @q)}
              id={"level-group-#{slug(level)}"}
              level={level}
              classes={length(rows)}
              students={Enum.sum_by(rows, & &1.count)}
            >
              <div class={[
                "ta-section overflow-x-auto",
                @mode != :designate && "hidden sm:block"
              ]}>
                <table class="table table-fixed">
                  <colgroup>
                    <col class="w-[26%]" />
                    <col class={["w-[11%]", @mode == :designate && "max-sm:hidden"]} />
                    <col class="w-[30%]" />
                    <col class={["w-[20%]", @mode == :designate && "max-sm:hidden"]} />
                    <col class={["w-[13%]", @mode == :designate && "max-sm:hidden"]} />
                  </colgroup>
                  <thead>
                    <tr class="text-xs text-base-content/70">
                      <th>{gettext("Classe")}</th>
                      <th class={@mode == :designate && "max-sm:hidden"}>{gettext("Élèves")}</th>
                      <th>{gettext("Professeur principal")}</th>
                      <th class={@mode == :designate && "max-sm:hidden"}>{gettext("Matières")}</th>
                      <th class={@mode == :designate && "max-sm:hidden"}>
                        <span class="sr-only">{gettext("Ouvrir")}</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <.class_row
                      :for={row <- rows}
                      row={row}
                      mode={@mode}
                      members={@members}
                      draft={@pp_draft[row.cg.id]}
                    />
                  </tbody>
                </table>
              </div>
              <div :if={@mode != :designate} class="ta-section overflow-hidden sm:hidden">
                <.list_row
                  :for={row <- rows}
                  id={"class-item-#{row.cg.id}"}
                  navigate={~p"/school/classes/#{row.cg.id}"}
                  title={row.cg.label}
                  meta={row_meta(row)}
                  meta_class={row.unassigned > 0 && "text-warning"}
                >
                  <:trailing>
                    <span class="ta-num text-sm text-base-content/75">{row.count}</span>
                  </:trailing>
                </.list_row>
              </div>
            </.level_group>
          </form>

          <p
            :if={@classes != [] and visible_groups(@classes, @filter, @q) == []}
            id="no-class-match"
            class="text-sm text-base-content/70"
          >
            {gettext("Aucune classe ne correspond à ce filtre.")}
          </p>

          <.empty_state
            :if={@classes == []}
            icon="hero-rectangle-group"
            title={gettext("No classes yet")}
          />
        <% end %>
      </section>

      <.drawer
        :if={@drawer?}
        id="new-class-drawer"
        eyebrow={gettext("Classes · %{year}", year: @year.name)}
        title={gettext("Nouvelle classe")}
        on_close={JS.push("close_drawer")}
      >
        <.new_class_form
          nc={@nc}
          form={@class_form}
          error={@class_error}
          members={@members}
          profile={@profile}
        />
        <:footer>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="close_drawer">
            {gettext("Annuler")}
          </button>
          <button
            type="submit"
            form="class-form"
            id="create-class"
            class="btn btn-primary btn-sm"
            disabled={@nc.duplicate? or @nc.label == ""}
          >
            {gettext("Créer la classe %{label}", label: @nc.label)}
          </button>
        </:footer>
      </.drawer>
    </Layouts.app>
    """
  end

  attr :row, :map, required: true
  attr :mode, :atom, required: true
  attr :members, :list, required: true
  attr :draft, :string, default: nil

  defp class_row(assigns) do
    ~H"""
    <tr id={"class-row-#{@row.cg.id}"} class="hover:bg-base-200/40">
      <td class="font-semibold">
        <.link navigate={~p"/school/classes/#{@row.cg.id}"} class="hover:underline">
          {@row.cg.label}
        </.link>
      </td>
      <td class={@mode == :designate && "max-sm:hidden"}>
        <span
          id={"class-size-#{@row.cg.id}"}
          class={[
            "ta-num text-sm",
            @row.capacity.over? && "font-semibold text-error",
            @row.capacity.near? && "font-semibold text-warning"
          ]}
          title={
            @row.capacity.max &&
              gettext("Effectif maximum : %{max}", max: @row.capacity.max)
          }
        >
          {if @row.capacity.max && (@row.capacity.over? || @row.capacity.near?),
            do: "#{@row.count} / #{@row.capacity.max}",
            else: @row.count}
        </span>
      </td>
      <td>
        <select
          :if={@mode == :designate}
          id={"pp-#{@row.cg.id}"}
          name={"pp[#{@row.cg.id}]"}
          aria-label={gettext("Professeur principal de %{label}", label: @row.cg.label)}
          class={[
            "select select-sm w-full",
            if(@draft in [nil, ""],
              do: "border-dashed text-base-content/70",
              else: "border-primary bg-primary/10"
            )
          ]}
        >
          <option value="">{gettext("Choisir un enseignant…")}</option>
          <option
            :for={m <- @members}
            value={m.user_id}
            selected={m.user_id == @draft}
          >
            {User.display_name(m.user)}
          </option>
        </select>
        <span
          :if={@mode != :designate}
          id={"class-pp-#{@row.cg.id}"}
          class={["text-sm", !@row.pp && "text-warning"]}
        >
          {@row.pp || gettext("à désigner")}
        </span>
      </td>
      <td class={@mode == :designate && "max-sm:hidden"}>
        <span
          id={"class-unassigned-#{@row.cg.id}"}
          class={[
            "text-sm",
            if(@row.unassigned > 0, do: "font-medium text-warning", else: "text-base-content/70")
          ]}
        >
          {subjects_text(@row)}
        </span>
      </td>
      <td class={["text-right", @mode == :designate && "max-sm:hidden"]}>
        <.link
          navigate={~p"/school/classes/#{@row.cg.id}"}
          class="whitespace-nowrap text-sm font-semibold text-primary"
          aria-label={gettext("Ouvrir %{label}", label: @row.cg.label)}
        >
          {gettext("Ouvrir →")}
        </.link>
      </td>
    </tr>
    """
  end

  defp subjects_text(%{unassigned: 0, assigned: 0}), do: gettext("Aucune matière")

  defp subjects_text(%{unassigned: 0, assigned: n}),
    do: gettext("%{assigned} / %{total} affectées", assigned: n, total: n)

  defp subjects_text(%{unassigned: missing}),
    do: ngettext("%{count} sans enseignant", "%{count} sans enseignant", missing)

  defp row_meta(row) do
    [
      ngettext("%{count} élève", "%{count} élèves", row.count),
      gettext("PP : %{name}", name: row.pp || gettext("à désigner")),
      row.unassigned > 0 && subjects_text(row)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  attr :nc, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil
  attr :members, :list, required: true
  attr :profile, :any, required: true

  defp new_class_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="class-form"
      phx-change="validate_class"
      phx-submit="create_class"
      class="space-y-5"
    >
      <div :if={@error} id="class-error" role="alert" class="alert alert-error alert-soft">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>{@error}</span>
      </div>
      <fieldset :if={length(@nc.subsystems) > 1} class="space-y-2">
        <legend class="ta-eyebrow mb-2">{gettext("Sous-système")}</legend>
        <div class="flex flex-wrap gap-2">
          <.chip_radio
            :for={sub <- @nc.subsystems}
            id={"nc-subsystem-#{sub}"}
            name="nc[subsystem]"
            value={to_string(sub)}
            checked={@nc.subsystem == sub}
          >
            {if sub == :anglophone, do: gettext("Anglophone"), else: gettext("Francophone")}
          </.chip_radio>
        </div>
      </fieldset>

      <fieldset class="space-y-2">
        <legend class="ta-eyebrow mb-2">{gettext("Niveau")}</legend>
        <div class="flex flex-wrap gap-2">
          <.chip_radio
            :for={level <- @nc.levels}
            id={"nc-level-#{slug(level)}"}
            name="nc[level]"
            value={level}
            checked={@nc.level_choice == level}
          >
            {level}
          </.chip_radio>
          <.chip_radio
            id="nc-level-other"
            name="nc[level]"
            value={other_level()}
            checked={@nc.level_choice == other_level()}
          >
            {gettext("Autre…")}
          </.chip_radio>
        </div>
        <.input
          :if={@nc.level_choice == other_level()}
          id="nc-other-level"
          type="text"
          name="nc[other_level]"
          value={@nc.other_level}
          phx-debounce="200"
          placeholder={gettext("Nom du niveau")}
          aria-label={gettext("Nom du niveau")}
          class="input input-sm w-full"
        />
      </fieldset>

      <fieldset :if={@nc.series != []} class="space-y-2">
        <legend class="ta-eyebrow mb-2">{SchoolTemplates.stream_label(@nc.stream_kind)}</legend>
        <div class="flex flex-wrap gap-2">
          <.chip_radio id="nc-serie-none" name="nc[serie]" value="" checked={@nc.serie == nil}>
            {gettext("Aucune")}
          </.chip_radio>
          <.chip_radio
            :for={serie <- @nc.series}
            id={"nc-serie-#{slug(serie)}"}
            name="nc[serie]"
            value={serie}
            checked={@nc.serie == serie}
          >
            {serie}
          </.chip_radio>
        </div>
      </fieldset>

      <div class="grid gap-4 sm:grid-cols-2">
        <div class="space-y-1">
          <label for="nc-suffix" class="ta-eyebrow block">{gettext("Suffixe")}</label>
          <.input
            id="nc-suffix"
            type="text"
            name="nc[suffix]"
            value={@nc.suffix}
            phx-debounce="200"
            class="input input-sm w-full"
          />
          <span class="block text-xs text-base-content/70">{@nc.suffix_hint}</span>
        </div>
        <div class="space-y-1">
          <label for={@form[:max_size].id} class="ta-eyebrow block">
            {gettext("Effectif maximum")}
          </label>
          <.input
            field={@form[:max_size]}
            type="number"
            min="1"
            max="200"
            placeholder={@profile && @profile.max_class_size && to_string(@profile.max_class_size)}
            class="input input-sm w-full"
          />
          <span class="block text-xs text-base-content/70">
            {gettext("Alerte au-delà, sans bloquer")}
          </span>
        </div>
      </div>

      <div class="space-y-1">
        <label for={@form[:form_master_user_id].id} class="ta-eyebrow block">
          {gettext("Professeur principal (facultatif)")}
        </label>
        <.input
          field={@form[:form_master_user_id]}
          type="select"
          prompt={gettext("À désigner plus tard")}
          options={Enum.map(@members, &{User.display_name(&1.user), &1.user_id})}
          class="select select-sm w-full"
        />
      </div>

      <div
        id="nc-preview"
        class={[
          "rounded-[0.6rem] border border-dashed px-4 py-3",
          if(@nc.duplicate?, do: "border-error/60", else: "border-base-300")
        ]}
      >
        <span class="ta-eyebrow block">{gettext("Aperçu")}</span>
        <span class="font-display text-2xl font-semibold">{@nc.label}</span>
        <span :if={@nc.duplicate?} id="nc-duplicate" class="block text-sm text-error">
          {gettext("Une classe porte déjà ce nom.")}
        </span>
      </div>
    </.form>
    """
  end

  # --- Events ---------------------------------------------------------------------

  def handle_event("filter_text", %{"q" => q}, socket), do: {:noreply, assign(socket, :q, q)}

  def handle_event("draft_pp", %{"pp" => pp}, socket) when socket.assigns.mode == :designate do
    known = MapSet.new(socket.assigns.members, & &1.user_id)

    draft =
      Enum.reduce(pp, socket.assigns.pp_draft, fn {cg_id, user_id}, draft ->
        if Map.has_key?(draft, cg_id) and (user_id == "" or MapSet.member?(known, user_id)),
          do: Map.put(draft, cg_id, user_id),
          else: draft
      end)

    {:noreply,
     assign(socket,
       pp_draft: draft,
       pp_changes: length(pp_changes(socket.assigns.classes, draft))
     )}
  end

  def handle_event("save_pps", params, socket) when socket.assigns.mode == :designate do
    {:noreply, socket} = handle_event("draft_pp", Map.put_new(params, "pp", %{}), socket)
    changes = pp_changes(socket.assigns.classes, socket.assigns.pp_draft)

    case Enrollment.set_form_masters(socket.assigns.current_scope, changes) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           ngettext(
             "%{count} professeur principal enregistré.",
             "%{count} professeurs principaux enregistrés.",
             length(updated)
           )
         )
         |> load_classes()
         |> push_patch(to: classes_path(socket.assigns.filter, nil))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Les professeurs principaux n'ont pas été enregistrés.")
         )}
    end
  end

  def handle_event(event, _params, socket) when event in ["draft_pp", "save_pps"],
    do: {:noreply, socket}

  def handle_event("open_drawer", _params, socket) when socket.assigns.can_manage_classes? do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(
       drawer?: true,
       members: Accounts.list_members(scope),
       class_form: class_form(scope, socket.assigns.year),
       class_error: nil
     )
     |> assign_nc(%{})}
  end

  def handle_event("close_drawer", _params, socket),
    do: {:noreply, assign(socket, :drawer?, false)}

  def handle_event("validate_class", params, socket) when socket.assigns.drawer? do
    socket = assign_nc(socket, params["nc"] || %{}, socket.assigns.nc)

    form =
      AshPhoenix.Form.validate(
        socket.assigns.class_form,
        submit_params(socket.assigns.nc, params, socket.assigns.members)
      )

    {:noreply, assign(socket, class_form: form, class_error: nil)}
  end

  def handle_event("create_class", params, socket) when socket.assigns.drawer? do
    socket = assign_nc(socket, params["nc"] || %{}, socket.assigns.nc)
    nc = socket.assigns.nc

    if nc.duplicate? or nc.label == "" do
      {:noreply, socket}
    else
      case AshPhoenix.Form.submit(socket.assigns.class_form,
             params: submit_params(nc, params, socket.assigns.members)
           ) do
        {:ok, cg} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Classe %{label} créée.", label: cg.label))
           |> push_navigate(to: ~p"/school/classes/#{cg.id}")}

        {:error, form} ->
          if Authz.forbidden_form?(form),
            do: {:noreply, Authz.put_not_allowed(socket)},
            else: {:noreply, assign(socket, class_form: form, class_error: hidden_error(form))}
      end
    end
  end

  # Forged or stale events (no drawer open, or not allowed to open one).
  def handle_event(event, _params, socket)
      when event in ["open_drawer", "validate_class", "create_class"],
      do: {:noreply, socket}

  # --- Data -----------------------------------------------------------------------

  defp load_classes(socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    classes =
      if year do
        cgs = Enrollment.list_class_groups(scope, year, load: [:enrollment_count, :form_master])
        status = Curriculum.assignment_status_by_class(scope, cgs)
        school_max = socket.assigns.profile && socket.assigns.profile.max_class_size

        cgs
        |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)
        |> Enum.map(fn cg ->
          %{
            cg: cg,
            count: cg.enrollment_count,
            capacity: Enrollment.capacity_of(cg.enrollment_count, cg.max_size || school_max),
            pp: cg.form_master && User.display_name(cg.form_master),
            unassigned: length(status[cg.id].unassigned),
            assigned: status[cg.id].assigned,
            search: fold("#{cg.label} #{cg.level} #{cg.serie}")
          }
        end)
      else
        []
      end

    assign(socket, classes: classes, year: year, counts: filter_counts(classes))
  end

  defp visible_groups(classes, filter, q) do
    needle = fold(q)

    classes
    |> Enum.filter(&(matches_filter?(&1, filter) and String.contains?(&1.search, needle)))
    |> Enum.chunk_by(& &1.cg.level)
    |> Enum.map(fn [first | _] = rows -> {first.cg.level || gettext("Autres"), rows} end)
  end

  defp matches_filter?(_row, :all), do: true
  defp matches_filter?(row, :no_pp), do: row.cg.form_master_user_id == nil
  defp matches_filter?(row, :to_assign), do: row.unassigned > 0

  defp filter_counts(classes),
    do: Map.new(@filters, fn f -> {f, Enum.count(classes, &matches_filter?(&1, f))} end)

  defp filter_label(:all), do: gettext("Toutes")
  defp filter_label(:no_pp), do: gettext("Sans PP")
  defp filter_label(:to_assign), do: gettext("Matières à affecter")

  defp classes_path(filter, mode) do
    query =
      [f: filter != :all && filter, mode: mode]
      |> Enum.filter(fn {_k, v} -> v end)

    if query == [], do: ~p"/school/classes", else: ~p"/school/classes?#{query}"
  end

  defp header_subtitle(classes) do
    levels = classes |> Enum.map(& &1.cg.level) |> Enum.uniq() |> length()

    Enum.join(
      [
        ngettext("%{count} classe", "%{count} classes", length(classes)),
        ngettext("%{count} élève", "%{count} élèves", Enum.sum_by(classes, & &1.count)),
        ngettext("%{count} niveau", "%{count} niveaux", levels)
      ],
      " · "
    )
  end

  # Case- and accent-insensitive: « Élève » matches « eleve ».
  defp fold(nil), do: ""

  defp fold(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.trim()
  end

  # --- « Nouvelle classe » --------------------------------------------------------

  defp other_level, do: @other_level

  # The drawer's state: what the chips and the suffix say, and the label they make.
  defp assign_nc(socket, params, previous \\ nil) do
    profile = socket.assigns.profile
    type = profile && profile.school_type
    school_sub = (profile && profile.subsystem) || :francophone
    subsystems = SchoolTemplates.grid_subsystems(school_sub)

    current = previous && previous.subsystem

    subsystem =
      Enum.find(subsystems, current || hd(subsystems), &(to_string(&1) == params["subsystem"]))

    levels = SchoolTemplates.levels_for(type, subsystem)
    level_choice = params["level"] || (previous && previous.level_choice) || hd(levels)

    level_choice =
      if level_choice in levels or level_choice == @other_level,
        do: level_choice,
        else: hd(levels)

    other = String.trim(params["other_level"] || "")
    level = if level_choice == @other_level, do: other, else: level_choice

    streams = SchoolTemplates.streams_for(type, subsystem)
    series = if level in streams.levels, do: streams.values, else: []
    serie = if params["serie"] in series, do: params["serie"], else: nil

    base = Enum.join(Enum.reject([level, serie], &(&1 in [nil, ""])), " ")
    existing = Enum.map(socket.assigns.classes, & &1.cg.label)

    # Classes of the same level and série, whatever their label's spelling
    # (« 6e A » is a 6ème class): their last word is the suffix they use.
    siblings =
      socket.assigns.classes
      |> Enum.map(& &1.cg)
      |> Enum.filter(&(&1.subsystem == subsystem and &1.level == level and &1.serie == serie))
      |> Enum.map(& &1.label)
      |> Enum.sort()

    taken = Enum.map(siblings, &"#{base} #{&1 |> String.split() |> List.last()}")

    # The suffix follows level and série until the admin edits it.
    same_base? = previous != nil and previous.base == base

    suffix =
      cond do
        same_base? and is_binary(params["suffix"]) -> String.trim(params["suffix"])
        base == "" -> ""
        true -> next_suffix(base, taken, profile)
      end

    label = Enum.join(Enum.reject([base, suffix], &(&1 == "")), " ")

    assign(socket, :nc, %{
      subsystems: subsystems,
      subsystem: subsystem,
      levels: levels,
      level_choice: level_choice,
      other_level: other,
      level: level,
      series: series,
      serie: serie,
      stream_kind: streams.kind,
      base: base,
      suffix: suffix,
      label: label,
      duplicate?: label in existing or label in taken,
      suffix_hint:
        if(siblings == [],
          do: gettext("Aucune autre classe à ce niveau."),
          else: gettext("Déjà : %{labels}", labels: Enum.join(siblings, ", "))
        )
    })
  end

  defp next_suffix(base, existing, profile) do
    rule = (profile && profile.class_suffix) || :letters

    base
    |> SchoolTemplates.next_class_label(existing, rule)
    |> String.replace_prefix(base <> " ", "")
  end

  # The form master must be one of the school's members (as `set_form_master/3`).
  defp submit_params(nc, params, members) do
    form = params["class_group"] || %{}
    pp = form["form_master_user_id"]
    pp = if Enum.any?(members, &(&1.user_id == pp)), do: pp, else: nil

    %{
      "label" => nc.label,
      "level" => nc.level,
      "serie" => nc.serie,
      "subsystem" => to_string(nc.subsystem),
      "max_size" => form["max_size"],
      "form_master_user_id" => pp
    }
  end

  # `academic_year_id` is server-controlled, set on the changeset through
  # `prepare_source` rather than merged into the submitted params.
  # A refusal no field of the drawer shows: the name (built, not typed — another admin
  # may have just taken it) or the whole class (a closed year).
  defp hidden_error(form) do
    errors =
      form
      |> AshPhoenix.Form.raw_errors()
      |> Enum.reject(&(Map.get(&1, :field) in [:max_size, :form_master_user_id]))

    cond do
      errors == [] ->
        nil

      Enum.any?(errors, &(Map.get(&1, :field) == :label)) ->
        gettext("Une classe porte déjà ce nom.")

      true ->
        Authz.failure_message(Ash.Error.to_error_class(errors))
    end
  end

  defp class_form(scope, year) do
    ClassGroup
    |> AshPhoenix.Form.for_create(:create,
      as: "class_group",
      scope: scope,
      prepare_source: fn changeset ->
        Ash.Changeset.change_attribute(changeset, :academic_year_id, year && year.id)
      end
    )
    |> to_form()
  end

  defp slug(text), do: text |> fold() |> String.replace(~r/[^a-z0-9]+/, "-")
end
