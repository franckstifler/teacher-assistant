defmodule TeacherAssistantWeb.School.ClassesLive do
  @moduledoc """
  The school's classes (spec 2026-10-08 §2): cards grouped by cycle, a cycle and
  text filter, and the « Nouvelle classe » drawer that builds the label from
  level, série and suffix.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Drawer

  alias TeacherAssistant.{Accounts, Curriculum, Enrollment}
  alias TeacherAssistant.Academics.{ClassGroup, SchoolTemplates}
  alias TeacherAssistant.Accounts.User

  @cycles [:first, :second, :anglophone, :other]
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
         profile: profile,
         can_manage_classes?: Enrollment.can_manage_classes?(scope),
         cycle: :all,
         q: "",
         drawer?: false
       )
       |> load_classes()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-classes" class="space-y-6">
        <.page_header
          eyebrow={gettext("Établissement")}
          title={gettext("Classes")}
          subtitle={
            @year &&
              gettext("%{classes} · %{students}",
                classes: ngettext("%{count} classe", "%{count} classes", length(@classes)),
                students:
                  ngettext("%{count} élève", "%{count} élèves", Enum.sum_by(@classes, & &1.count))
              )
          }
        >
          <:actions>
            <button
              :if={@year && @can_manage_classes?}
              id="new-class-button"
              type="button"
              class="btn btn-primary btn-sm gap-1.5"
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
          <div
            :if={@classes != []}
            class="flex flex-wrap items-center gap-3 rounded-[0.6rem] border border-base-300 bg-base-100 px-3 py-2.5"
          >
            <div
              id="cycle-filter"
              role="group"
              aria-label={gettext("Cycle")}
              class="flex flex-wrap gap-1"
            >
              <button
                :for={cycle <- [:all | present_cycles(@classes)]}
                id={"cycle-#{cycle}"}
                type="button"
                phx-click="filter_cycle"
                phx-value-cycle={cycle}
                aria-pressed={to_string(@cycle == cycle)}
                class={[
                  "rounded-full px-3 py-1 text-sm font-semibold transition-colors",
                  if(@cycle == cycle,
                    do: "bg-primary/15 text-primary",
                    else: "text-base-content/70 hover:text-base-content"
                  )
                ]}
              >
                {cycle_label(cycle)}
              </button>
            </div>
            <form id="class-filter" phx-change="filter_text" class="min-w-48 flex-1">
              <label class="input input-sm w-full">
                <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                <input
                  type="search"
                  name="q"
                  value={@q}
                  phx-debounce="150"
                  placeholder={gettext("Filtrer : 6ème, Tle D, Form…")}
                  aria-label={gettext("Filtrer les classes")}
                />
              </label>
            </form>
            <span class="flex gap-3 text-xs text-base-content/70">
              <span class="inline-flex items-center gap-1.5">
                <span class="size-2 rounded-sm bg-error"></span>{gettext("À compléter")}
              </span>
              <span class="inline-flex items-center gap-1.5">
                <span class="size-2 rounded-sm bg-warning"></span>{gettext("Presque pleine")}
              </span>
            </span>
          </div>

          <section
            :for={{cycle, rows} <- visible_groups(@classes, @cycle, @q)}
            id={"cycle-group-#{cycle}"}
            class="space-y-3"
          >
            <div class="flex items-baseline gap-3">
              <h2 class="font-display text-xl font-semibold">{cycle_label(cycle)}</h2>
              <span class="ta-num text-xs text-base-content/60">
                {ngettext("%{count} classe", "%{count} classes", length(rows))} · {ngettext(
                  "%{count} élève",
                  "%{count} élèves",
                  Enum.sum_by(rows, & &1.count)
                )}
              </span>
            </div>
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              <.class_card :for={row <- rows} row={row} />
            </div>
          </section>

          <p
            :if={@classes != [] and visible_groups(@classes, @cycle, @q) == []}
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
        <.new_class_form nc={@nc} form={@class_form} members={@members} profile={@profile} />
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

  defp class_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/school/classes/#{@row.cg.id}"}
      id={"class-card-#{@row.cg.id}"}
      class={[
        "group flex flex-col gap-3 rounded-[0.6rem] border border-l-4 bg-base-100 p-4 transition",
        "hover:-translate-y-0.5 hover:border-primary/60 hover:shadow-md",
        if(@row.unassigned > 0, do: "border-base-300 border-l-error", else: "border-base-300")
      ]}
    >
      <span class="flex items-start justify-between gap-2">
        <span class="font-display text-lg font-semibold leading-tight">{@row.cg.label}</span>
        <span class="ta-num rounded bg-base-200 px-1.5 py-0.5 text-[0.7rem] text-base-content/70">
          {@row.cg.serie || @row.cg.level}
        </span>
      </span>
      <span class="space-y-1.5">
        <span class="flex justify-between text-xs text-base-content/70">
          <span>{gettext("Effectif")}</span>
          <span
            id={"class-size-#{@row.cg.id}"}
            class={[
              "ta-num",
              @row.capacity.over? && "font-semibold text-error",
              @row.capacity.near? && "font-semibold text-warning"
            ]}
          >
            {if @row.capacity.max,
              do: "#{@row.count} / #{@row.capacity.max}",
              else: @row.count}
          </span>
        </span>
        <span :if={@row.capacity.max} class="block h-1.5 overflow-hidden rounded-full bg-base-300">
          <span
            class={[
              "block h-full rounded-full",
              cond do
                @row.capacity.over? -> "bg-error"
                @row.capacity.near? -> "bg-warning"
                true -> "bg-primary"
              end
            ]}
            style={"width: #{min(100, round(@row.count * 100 / @row.capacity.max))}%"}
          ></span>
        </span>
      </span>
      <span class="flex flex-wrap justify-between gap-x-3 gap-y-1 text-xs">
        <span class="text-base-content/70">
          {gettext("PP :")}
          <span class="font-semibold text-base-content">{@row.pp || gettext("à désigner")}</span>
        </span>
        <span
          id={"class-unassigned-#{@row.cg.id}"}
          class={if @row.unassigned > 0, do: "font-semibold text-error", else: "text-base-content/60"}
        >
          {if @row.unassigned > 0,
            do:
              ngettext(
                "%{count} matière sans enseignant",
                "%{count} matières sans enseignant",
                @row.unassigned
              ),
            else: ngettext("%{count} matière affectée", "%{count} matières affectées", @row.assigned)}
        </span>
      </span>
    </.link>
    """
  end

  attr :nc, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
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
        <input
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
        <label class="block space-y-1">
          <span class="ta-eyebrow block">{gettext("Suffixe")}</span>
          <input
            id="nc-suffix"
            type="text"
            name="nc[suffix]"
            value={@nc.suffix}
            phx-debounce="200"
            class="input input-sm w-full"
          />
          <span class="block text-xs text-base-content/60">{@nc.suffix_hint}</span>
        </label>
        <div class="space-y-1">
          <.input
            field={@form[:max_size]}
            type="number"
            min="1"
            max="200"
            label={gettext("Effectif maximum")}
            placeholder={@profile && @profile.max_class_size && to_string(@profile.max_class_size)}
            class="input input-sm w-full"
          />
          <span class="block text-xs text-base-content/60">
            {gettext("Alerte au-delà, sans bloquer")}
          </span>
        </div>
      </div>

      <.input
        field={@form[:form_master_user_id]}
        type="select"
        label={gettext("Professeur principal (facultatif)")}
        prompt={gettext("À désigner plus tard")}
        options={Enum.map(@members, &{User.display_name(&1.user), &1.user_id})}
        class="select select-sm w-full"
      />

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

  def handle_event("filter_cycle", %{"cycle" => cycle}, socket) do
    cycle = Enum.find([:all | @cycles], :all, &(to_string(&1) == cycle))
    {:noreply, assign(socket, :cycle, cycle)}
  end

  def handle_event("filter_text", %{"q" => q}, socket), do: {:noreply, assign(socket, :q, q)}

  def handle_event("open_drawer", _params, socket) when socket.assigns.can_manage_classes? do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(
       drawer?: true,
       members: Accounts.list_members(scope),
       class_form: class_form(scope, socket.assigns.year)
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
        submit_params(socket.assigns.nc, params)
      )

    {:noreply, assign(socket, :class_form, form)}
  end

  def handle_event("create_class", params, socket) when socket.assigns.drawer? do
    socket = assign_nc(socket, params["nc"] || %{}, socket.assigns.nc)
    nc = socket.assigns.nc

    if nc.duplicate? or nc.label == "" do
      {:noreply, socket}
    else
      case AshPhoenix.Form.submit(socket.assigns.class_form, params: submit_params(nc, params)) do
        {:ok, cg} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Classe %{label} créée.", label: cg.label))
           |> push_navigate(to: ~p"/school/classes/#{cg.id}")}

        {:error, form} ->
          if Authz.forbidden_form?(form),
            do: {:noreply, Authz.put_not_allowed(socket)},
            else: {:noreply, assign(socket, :class_form, form)}
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
        unassigned = Curriculum.unassigned_subjects_by_class(scope, cgs)
        assigned = Curriculum.assignment_counts_by_class(scope, cgs)
        school_max = socket.assigns.profile && socket.assigns.profile.max_class_size

        cgs
        |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)
        |> Enum.map(fn cg ->
          %{
            cg: cg,
            count: cg.enrollment_count,
            capacity: Enrollment.capacity_of(cg.enrollment_count, cg.max_size || school_max),
            pp: cg.form_master && User.display_name(cg.form_master),
            unassigned: length(unassigned[cg.id]),
            assigned: Map.get(assigned, cg.id, 0),
            cycle: SchoolTemplates.cycle(cg.level, cg.subsystem),
            search: fold("#{cg.label} #{cg.level} #{cg.serie}")
          }
        end)
      else
        []
      end

    assign(socket, classes: classes, year: year)
  end

  defp present_cycles(classes) do
    present = MapSet.new(classes, & &1.cycle)
    Enum.filter(@cycles, &MapSet.member?(present, &1))
  end

  defp visible_groups(classes, cycle, q) do
    needle = fold(q)

    classes
    |> Enum.filter(&(cycle in [:all, &1.cycle] and String.contains?(&1.search, needle)))
    |> Enum.group_by(& &1.cycle)
    |> then(fn groups -> for c <- @cycles, rows = groups[c], do: {c, rows} end)
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

  defp cycle_label(:all), do: gettext("Toutes")
  defp cycle_label(:first), do: gettext("1er cycle")
  defp cycle_label(:second), do: gettext("2nd cycle")
  defp cycle_label(:anglophone), do: gettext("Anglophone")
  defp cycle_label(:other), do: gettext("Autres")

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

    # The suffix follows level and série until the admin edits it.
    same_base? = previous != nil and previous.base == base

    suffix =
      cond do
        same_base? and is_binary(params["suffix"]) -> String.trim(params["suffix"])
        base == "" -> ""
        true -> next_suffix(base, existing, profile)
      end

    label = Enum.join(Enum.reject([base, suffix], &(&1 == "")), " ")
    at_level = existing |> Enum.filter(&String.starts_with?(&1, base <> " ")) |> Enum.sort()

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
      duplicate?: label in existing,
      suffix_hint:
        if(at_level == [],
          do: gettext("Aucune autre classe à ce niveau."),
          else: gettext("Déjà : %{labels}", labels: Enum.join(at_level, ", "))
        )
    })
  end

  defp next_suffix(base, existing, profile) do
    rule = (profile && profile.class_suffix) || :letters

    base
    |> SchoolTemplates.next_class_label(existing, rule)
    |> String.replace_prefix(base <> " ", "")
  end

  defp submit_params(nc, params) do
    form = params["class_group"] || %{}

    %{
      "label" => nc.label,
      "level" => nc.level,
      "serie" => nc.serie,
      "subsystem" => to_string(nc.subsystem),
      "max_size" => form["max_size"],
      "form_master_user_id" => form["form_master_user_id"]
    }
  end

  # `academic_year_id` is server-controlled, set on the changeset through
  # `prepare_source` rather than merged into the submitted params.
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
