defmodule TeacherAssistantWeb.School.FeeSettingsLive do
  @moduledoc """
  Paramètres des frais (Fees 1, rule 25; UX refonte 2026-11-03): three numbered steps
  unlocking in order — the fee types as chips (presets by the school's sector, « + Autre »;
  names and payment order in a secondary panel), the amounts one row per level with each
  class adjustable, the cumulative tranches — then carrying last year's unpaid fees.
  Fees axis (Proviseur, Censeur, Intendant).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Enrollment, Fees, Organization}
  alias TeacherAssistant.Academics.SchoolTemplates
  alias TeacherAssistantWeb.Money

  import TeacherAssistantWeb.FeeSetupComponents

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Fees.can_manage_fees?(scope),
         %{} = year <- Organization.current_academic_year(scope) do
      {:ok,
       socket
       |> assign(
         page_title: gettext("Paramètres des frais"),
         year: year,
         presets: Fees.fee_type_presets(sector(scope)),
         unmatched: nil,
         type_error: nil,
         tranche_error: nil
       )
       |> reset_forms()
       |> load()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp scope(socket), do: socket.assigns.current_scope

  defp sector(scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, %{sector: sector}} -> sector
      _ -> :public
    end
  end

  defp load(socket) do
    %{year: year} = socket.assigns
    types = Fees.list_fee_types(scope(socket), year)

    assign(socket,
      types: types,
      regular: Enum.filter(types, &(&1.kind == :regular and &1.active?)),
      classes:
        scope(socket)
        |> Enrollment.list_class_groups(year, load: [:enrollment_count])
        |> Enum.sort_by(&SchoolTemplates.class_sort_key/1),
      status: Fees.setup_status(scope(socket), year),
      grid: Fees.class_fee_grid(scope(socket), year),
      tranches: Fees.list_tranches(scope(socket), year),
      arrears: Fees.arrears_candidates(scope(socket), year)
    )
  end

  # Forms come from the server so they empty after a save.
  defp reset_forms(socket),
    do:
      assign(socket,
        type_form: to_form(%{"name" => ""}, as: :fee_type),
        tranche_form: to_form(%{"label" => "", "due_date" => "", "percent" => ""}, as: :tranche),
        editing_tranche: nil
      )

  # --- fee types ---------------------------------------------------------------------

  def handle_event("create_default_types", _params, socket) do
    %{year: year, presets: presets} = socket.assigns
    result(socket, Fees.create_default_fee_types(scope(socket), year, presets.defaults))
  end

  # A chip: on → withdrawn (refused while in use), off → back, or created.
  def handle_event("toggle_type", %{"name" => name}, socket) do
    case Enum.find(socket.assigns.types, &(&1.kind == :regular and same_name?(&1.name, name))) do
      %{active?: true} = type ->
        deactivate(socket, type)

      %{active?: false} = type ->
        result(socket, Fees.reactivate_fee_type(scope(socket), type))

      nil ->
        result(socket, Fees.create_fee_type(scope(socket), socket.assigns.year, %{name: name}))
    end
  end

  def handle_event("change_type", %{"fee_type" => params}, socket),
    do: {:noreply, assign(socket, type_form: to_form(params, as: :fee_type))}

  def handle_event("add_type", %{"fee_type" => %{"name" => name}}, socket) do
    case Fees.create_fee_type(scope(socket), socket.assigns.year, %{name: name}) do
      {:ok, _} ->
        {:noreply, socket |> assign(type_error: nil) |> reset_forms() |> load()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, assign(socket, type_error: gettext("Ce nom est vide ou déjà utilisé."))}
    end
  end

  def handle_event("rename_type", %{"type_id" => id, "name" => name}, socket) do
    with %{} = type <- find_type(socket, id) do
      socket |> result(Fees.rename_fee_type(scope(socket), type, name))
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ["up", "down"] do
    with %{} = type <- find_type(socket, id) do
      direction = if dir == "up", do: :up, else: :down
      socket |> result(Fees.move_fee_type(scope(socket), type, direction))
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    case find_type(socket, id) do
      %{} = type -> deactivate(socket, type)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    with %{} = type <- find_type(socket, id) do
      result(socket, Fees.reactivate_fee_type(scope(socket), type))
    else
      _ -> {:noreply, socket}
    end
  end

  # --- class amounts -----------------------------------------------------------------

  def handle_event("set_fee", %{"cg" => cg_id, "type" => type_id, "amount" => raw}, socket) do
    with %{} = cg <- find_class(socket, cg_id),
         %{} = type <- find_type(socket, type_id),
         {:ok, amount} <- parse_amount(raw) do
      result(socket, Fees.set_class_fee(scope(socket), cg, type, amount))
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Montant invalide."))}
    end
  end

  def handle_event(
        "set_level_amount",
        %{"level" => level, "type" => type_id, "amount" => raw},
        socket
      ) do
    with true <- Enum.any?(socket.assigns.classes, &(&1.level == level)),
         %{} = type <- find_type(socket, type_id),
         {:ok, amount} <- parse_amount(raw) do
      result(socket, Fees.set_level_fees(scope(socket), socket.assigns.year, level, type, amount))
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Montant invalide."))}
    end
  end

  # --- tranches ----------------------------------------------------------------------

  def handle_event("change_tranche", %{"tranche" => params}, socket),
    do: {:noreply, assign(socket, tranche_form: to_form(params, as: :tranche))}

  def handle_event("save_tranche", %{"tranche" => params}, socket) do
    with {:ok, date} <- Date.from_iso8601(params["due_date"] || ""),
         {percent, ""} <- Integer.parse(params["percent"] || "") do
      attrs = %{label: params["label"], due_date: date, percent: percent}

      saved =
        case socket.assigns.editing_tranche do
          nil -> Fees.add_tranche(scope(socket), socket.assigns.year, attrs)
          tranche -> Fees.update_tranche(scope(socket), tranche, attrs)
        end

      case saved do
        {:ok, _} ->
          {:noreply, socket |> assign(tranche_error: nil) |> reset_forms() |> load()}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, :not_rising} ->
          {:noreply,
           socket
           |> tranche_error(params)
           |> assign(
             tranche_error:
               gettext("Une tranche plus tardive doit demander un pourcentage plus grand.")
           )}

        {:error, _} ->
          {:noreply, tranche_error(socket, params)}
      end
    else
      _ -> {:noreply, tranche_error(socket, params)}
    end
  end

  def handle_event("edit_tranche", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.tranches, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      t ->
        {:noreply,
         assign(socket,
           editing_tranche: t,
           tranche_form:
             to_form(
               %{
                 "label" => t.label,
                 "due_date" => Date.to_iso8601(t.due_date),
                 "percent" => to_string(t.percent)
               },
               as: :tranche
             )
         )}
    end
  end

  def handle_event("cancel_tranche", _params, socket),
    do: {:noreply, socket |> assign(tranche_error: nil) |> reset_forms()}

  def handle_event("delete_tranche", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.tranches, &(&1.id == id)) do
      nil -> {:noreply, socket}
      t -> result(socket, Fees.delete_tranche(scope(socket), t))
    end
  end

  # --- copy and arrears --------------------------------------------------------------

  def handle_event("copy_previous", _params, socket) do
    case Fees.copy_previous_year(scope(socket), socket.assigns.year) do
      {:ok, %{unmatched: unmatched}} ->
        {:noreply, socket |> assign(unmatched: unmatched) |> load()}

      {:error, :nothing_to_copy} ->
        {:noreply, put_flash(socket, :error, gettext("Aucune année précédente avec des frais."))}

      other ->
        result(socket, other)
    end
  end

  def handle_event("carry_arrears", params, socket) do
    ids = List.wrap(params["enrollment_ids"])

    case Fees.carry_arrears(scope(socket), socket.assigns.year, ids) do
      {:ok, n} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(
           :info,
           ngettext("%{count} reliquat reporté.", "%{count} reliquats reportés.", n)
         )}

      other ->
        result(socket, other)
    end
  end

  # --- helpers -----------------------------------------------------------------------

  defp result(socket, ok) when ok in [:ok] or elem(ok, 0) == :ok,
    do: {:noreply, load(socket)}

  defp result(socket, {:error, %Ash.Error.Forbidden{}}),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp result(socket, _error),
    do:
      {:noreply, socket |> put_flash(:error, gettext("Modification non enregistrée.")) |> load()}

  defp deactivate(socket, type) do
    case Fees.deactivate_fee_type(scope(socket), type) do
      {:error, :in_use} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "Ce frais est utilisé (montants ou paiements) : mettez ses montants à 0 d'abord."
           )
         )}

      other ->
        result(socket, other)
    end
  end

  defp same_name?(a, b), do: String.downcase(String.trim(a)) == String.downcase(String.trim(b))

  # The chips: the preset, its suggestions, then the school's own types.
  defp chips(presets, types) do
    regular = Enum.filter(types, &(&1.kind == :regular))

    names =
      (presets.defaults ++ presets.suggestions ++ Enum.map(regular, & &1.name))
      |> Enum.uniq_by(&String.downcase/1)

    Enum.map(names, fn name ->
      type = Enum.find(regular, &same_name?(&1.name, name))
      %{name: (type && type.name) || name, on?: type != nil and type.active?}
    end)
  end

  # One row per level, in class order: its classes and, per type, the amount they share
  # (nil when they differ or none is set).
  defp level_rows(classes, grid, types) do
    classes
    |> Enum.chunk_by(& &1.level)
    |> Enum.with_index()
    |> Enum.map(fn {[first | _] = group, i} ->
      amounts =
        Map.new(types, fn t ->
          values = group |> Enum.map(&Map.get(grid, {&1.id, t.id})) |> Enum.uniq()
          {t.id, if(match?([_], values), do: hd(values), else: :mixed)}
        end)

      %{index: i, level: first.level, classes: group, amounts: amounts}
    end)
  end

  defp level_total(row, types) do
    if Enum.any?(types, &(row.amounts[&1.id] == :mixed)),
      do: nil,
      else: types |> Enum.map(&(row.amounts[&1.id] || 0)) |> Enum.sum()
  end

  defp tranche_error(socket, params),
    do:
      assign(socket,
        tranche_form: to_form(params, as: :tranche),
        tranche_error: gettext("Indiquez une date et un pourcentage entre 1 et 100.")
      )

  defp find_type(socket, id), do: Enum.find(socket.assigns.types, &(&1.id == id))
  defp find_class(socket, id), do: Enum.find(socket.assigns.classes, &(&1.id == id))
  defp students(classes), do: Enum.sum_by(classes, &(&1.enrollment_count || 0))

  defp parse_amount(raw) when is_binary(raw) do
    case raw |> String.replace(~r/\s/u, "") |> Integer.parse() do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> if String.trim(raw) == "", do: {:ok, 0}, else: :error
    end
  end

  defp parse_amount(_raw), do: :error

  defp class_total(grid, types, cg),
    do: types |> Enum.map(&Map.get(grid, {cg.id, &1.id}, 0)) |> Enum.sum()

  defp last_percent(tranches),
    do: tranches |> List.last() |> then(&(&1 && &1.percent))

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="fee-settings" class="space-y-6">
        <%!-- Under Paramètres only for whom the menu has it; the intendant and the
             surveillant open this page from their own menu entry. --%>
        <.back_header
          back={
            TeacherAssistantWeb.Spaces.owner_item_for(@current_scope, ["settings"]) &&
              ~p"/school/settings"
          }
          back_label={gettext("Paramètres")}
          title={gettext("Paramètres des frais")}
          subtitle={@year.name}
        />

        <p class="-mt-4 text-sm text-base-content/70">
          {ngettext(
            "Trois réglages, puis l'encaissement, les reçus et le suivi des retards s'activent pour %{count} élève.",
            "Trois réglages, puis l'encaissement, les reçus et le suivi des retards s'activent pour les %{count} élèves.",
            students(@classes)
          )}
        </p>

        <ol id="fee-steps" class="flex flex-col gap-3">
          <.fee_step
            id="fee-types"
            n={1}
            state={step_state(1, @status.done)}
            title={gettext("Types de frais")}
            description={gettext("Cochez ceux que l'établissement perçoit.")}
          >
            <div class="flex flex-col gap-3">
              <div id="type-chips" class="flex flex-wrap gap-2">
                <button
                  :for={{chip, i} <- Enum.with_index(chips(@presets, @types))}
                  id={"type-chip-#{i}"}
                  type="button"
                  phx-click="toggle_type"
                  phx-value-name={chip.name}
                  aria-pressed={to_string(chip.on?)}
                  class={[
                    "inline-flex min-h-10 items-center gap-1.5 rounded-full border px-3.5 text-[0.85rem] transition-colors",
                    if(chip.on?,
                      do: "border-primary bg-primary/15 font-semibold text-primary",
                      else: "border-base-300 hover:border-base-content/40"
                    )
                  ]}
                >
                  <.icon :if={chip.on?} name="hero-check" class="size-3.5" />
                  {chip.name}
                </button>
                <details id="other-type" class="group">
                  <summary class="inline-flex min-h-10 cursor-pointer list-none items-center rounded-full border border-dashed border-base-300 px-3.5 text-[0.85rem] hover:border-base-content/40">
                    {gettext("+ Autre")}
                  </summary>
                  <.form
                    for={@type_form}
                    id="new-fee-type-form"
                    phx-change="change_type"
                    phx-submit="add_type"
                    class="mt-2 flex flex-wrap items-center gap-2"
                  >
                    <input
                      type="text"
                      name={@type_form[:name].name}
                      value={@type_form[:name].value}
                      placeholder="Frais informatique"
                      aria-label={gettext("Nouveau frais")}
                      class="input input-sm w-56"
                    />
                    <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter")}</button>
                  </.form>
                </details>
              </div>
              <p :if={@type_error} class="text-sm text-error">{@type_error}</p>

              <div :if={@types == []} class="flex flex-wrap items-center gap-2">
                <button
                  id="create-default-types"
                  type="button"
                  phx-click="create_default_types"
                  class="btn btn-primary btn-sm"
                >
                  {gettext("Prendre : %{names}", names: Enum.join(@presets.defaults, ", "))}
                </button>
                <button
                  id="copy-previous"
                  type="button"
                  phx-click="copy_previous"
                  class="btn btn-ghost btn-sm"
                >
                  {gettext("Copier l'année précédente")}
                </button>
              </div>

              <p
                :if={@unmatched not in [nil, []]}
                id="copy-unmatched"
                class="rounded-box bg-warning/15 p-3 text-sm"
              >
                {gettext("À compléter : %{classes}", classes: Enum.join(@unmatched, ", "))}
              </p>

              <details :if={@types != []} id="type-order" class="rounded-box border border-base-300">
                <summary class="flex min-h-11 cursor-pointer items-center gap-2 px-3 text-sm font-medium">
                  <.icon name="hero-arrows-up-down" class="size-4 text-base-content/70" />
                  {gettext("Ordre de paiement et noms")}
                </summary>
                <p class="px-3 pb-2 text-xs text-base-content/70">
                  {gettext(
                    "L'ordre est l'ordre de paiement : une somme versée règle d'abord le premier frais."
                  )}
                </p>
                <ol class="divide-y divide-base-300 border-t border-base-300">
                  <li
                    :for={{t, i} <- Enum.with_index(@types)}
                    id={"fee-type-#{t.id}"}
                    class={[
                      "flex flex-wrap items-center gap-2 px-3 py-1.5",
                      !t.active? && "opacity-60"
                    ]}
                  >
                    <span class="ta-num w-6 text-sm text-base-content/70">{i + 1}.</span>
                    <%= if t.kind == :arrears do %>
                      <span class="flex-1 font-semibold">{t.name}</span>
                      <span class="badge badge-ghost badge-sm">{gettext("toujours en premier")}</span>
                    <% else %>
                      <form id={"rename-type-#{t.id}"} phx-submit="rename_type" class="flex-1">
                        <input type="hidden" name="type_id" value={t.id} />
                        <input
                          name="name"
                          value={t.name}
                          aria-label={gettext("Nom du frais")}
                          class="input input-sm input-ghost w-full font-semibold"
                        />
                      </form>
                      <span :if={!t.active?} class="badge badge-ghost badge-sm">{gettext("Retiré")}</span>
                      <button
                        id={"move-up-#{t.id}"}
                        type="button"
                        phx-click="move"
                        phx-value-id={t.id}
                        phx-value-dir="up"
                        class="btn btn-ghost btn-xs"
                        aria-label={gettext("Monter")}
                      >
                        <.icon name="hero-arrow-up" class="size-4" />
                      </button>
                      <button
                        id={"move-down-#{t.id}"}
                        type="button"
                        phx-click="move"
                        phx-value-id={t.id}
                        phx-value-dir="down"
                        class="btn btn-ghost btn-xs"
                        aria-label={gettext("Descendre")}
                      >
                        <.icon name="hero-arrow-down" class="size-4" />
                      </button>
                      <button
                        :if={t.active?}
                        id={"deactivate-type-#{t.id}"}
                        type="button"
                        phx-click="deactivate"
                        phx-value-id={t.id}
                        class="btn btn-ghost btn-xs"
                      >
                        {gettext("Retirer")}
                      </button>
                      <button
                        :if={!t.active?}
                        id={"reactivate-type-#{t.id}"}
                        type="button"
                        phx-click="reactivate"
                        phx-value-id={t.id}
                        class="btn btn-ghost btn-xs"
                      >
                        {gettext("Rétablir")}
                      </button>
                    <% end %>
                  </li>
                </ol>
              </details>
            </div>
          </.fee_step>

          <.fee_step
            id="fee-grid"
            n={2}
            state={step_state(2, @status.done)}
            title={gettext("Montants par niveau")}
            description={
              gettext(
                "Un montant par niveau s'applique à toutes ses classes ; ajustez une classe ensuite si besoin. Laissez vide ou 0 quand un niveau ne paie pas ce frais."
              )
            }
            summary={
              @status.priced > 0 &&
                gettext("%{priced} classes sur %{total} ont leurs montants",
                  priced: @status.priced,
                  total: @status.classes
                )
            }
            open={@regular != []}
          >
            <div class="overflow-x-auto rounded-box border border-base-300">
              <table class="table table-sm">
                <thead>
                  <tr class="text-xs text-base-content/70">
                    <th class="sticky left-0 z-10 bg-base-100 font-medium">{gettext("Niveau")}</th>
                    <th :for={t <- @regular} class="font-medium">{t.name}</th>
                    <th class="text-right font-medium">{gettext("Total")}</th>
                  </tr>
                </thead>
                <tbody
                  :for={row <- level_rows(@classes, @grid, @regular)}
                  id={"level-row-#{row.index}"}
                >
                  <tr>
                    <td class="sticky left-0 z-10 whitespace-nowrap bg-base-100">
                      <span class="block font-semibold">{row.level}</span>
                      <span class="text-xs text-base-content/70">
                        {ngettext("%{count} classe", "%{count} classes", length(row.classes))}
                      </span>
                    </td>
                    <td :for={t <- @regular} class="min-w-32">
                      <form id={"level-fee-#{row.index}-#{t.id}"} phx-change="set_level_amount">
                        <input type="hidden" name="level" value={row.level} />
                        <input type="hidden" name="type" value={t.id} />
                        <input
                          name="amount"
                          inputmode="numeric"
                          phx-debounce="blur"
                          value={if row.amounts[t.id] != :mixed, do: row.amounts[t.id]}
                          placeholder={
                            if row.amounts[t.id] == :mixed, do: gettext("varie"), else: "FCFA"
                          }
                          aria-label={"#{row.level} · #{t.name}"}
                          class="input input-sm ta-num w-28 text-right"
                        />
                      </form>
                    </td>
                    <td class="ta-num whitespace-nowrap text-right text-sm">
                      {(total = level_total(row, @regular)) && Money.format_fcfa(total)}
                      <span :if={!level_total(row, @regular)} class="text-base-content/70">
                        {gettext("varie")}
                      </span>
                    </td>
                  </tr>
                  <tr :if={length(row.classes) > 1}>
                    <td colspan={length(@regular) + 2} class="!pt-0">
                      <details id={"level-classes-#{row.index}"}>
                        <summary class="cursor-pointer py-1 text-xs font-semibold text-primary">
                          {gettext("Ajuster une classe")}
                        </summary>
                        <div class="mt-1 flex flex-col gap-1.5">
                          <div
                            :for={cg <- row.classes}
                            id={"class-fees-#{cg.id}"}
                            class="flex flex-wrap items-center gap-2"
                          >
                            <span class="w-28 truncate text-sm font-medium">{cg.label}</span>
                            <form
                              :for={t <- @regular}
                              id={"fee-#{cg.id}-#{t.id}"}
                              phx-change="set_fee"
                            >
                              <input type="hidden" name="cg" value={cg.id} />
                              <input type="hidden" name="type" value={t.id} />
                              <input
                                name="amount"
                                inputmode="numeric"
                                phx-debounce="blur"
                                value={Map.get(@grid, {cg.id, t.id})}
                                aria-label={"#{cg.label} · #{t.name}"}
                                class="input input-xs ta-num w-24 text-right"
                              />
                            </form>
                            <span class="ta-num ml-auto text-xs text-base-content/70">
                              {Money.format_fcfa(class_total(@grid, @regular, cg))}
                            </span>
                          </div>
                        </div>
                      </details>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.fee_step>

          <.fee_step
            id="tranches"
            n={3}
            state={step_state(3, @status.done)}
            title={gettext("Tranches et échéances")}
            description={
              gettext(
                "Par exemple 3 tranches : rentrée, janvier, avril. Chaque tranche dit quelle part du total chaque élève doit avoir payée à sa date (cumulée) ; les retards se calculent à partir de ces dates."
              )
            }
            open={@status.done >= 2 or @tranches != []}
          >
            <div class="flex flex-col gap-3">
              <div :if={@tranches != []} class="overflow-x-auto rounded-box border border-base-300">
                <table class="table table-sm">
                  <tbody>
                    <tr :for={t <- @tranches} id={"tranche-#{t.id}"}>
                      <td class="whitespace-nowrap font-semibold">{t.label}</td>
                      <td class="ta-num whitespace-nowrap">{date(t.due_date)}</td>
                      <td class="ta-num whitespace-nowrap text-right">{t.percent} %</td>
                      <td class="whitespace-nowrap text-right">
                        <button
                          type="button"
                          phx-click="edit_tranche"
                          phx-value-id={t.id}
                          class="btn btn-ghost btn-xs"
                        >
                          {gettext("Modifier")}
                        </button>
                        <button
                          id={"delete-tranche-#{t.id}"}
                          type="button"
                          phx-click="delete_tranche"
                          phx-value-id={t.id}
                          data-confirm={gettext("Supprimer cette tranche ?")}
                          class="btn btn-ghost btn-xs text-error"
                        >
                          {gettext("Supprimer")}
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p
                :if={@tranches != [] and last_percent(@tranches) != 100}
                id="percent-warning"
                class="rounded-box bg-warning/15 p-3 text-sm"
              >
                {gettext(
                  "La dernière tranche devrait être à 100 % pour que tout le monde doive tout payer."
                )}
              </p>

              <.form
                for={@tranche_form}
                id="tranche-form"
                phx-change="change_tranche"
                phx-submit="save_tranche"
                class="grid items-end gap-2 sm:grid-cols-4"
              >
                <.input
                  field={@tranche_form[:label]}
                  label={gettext("Libellé")}
                  placeholder="1re tranche"
                />
                <.input field={@tranche_form[:due_date]} type="date" label={gettext("Date limite")} />
                <.input
                  field={@tranche_form[:percent]}
                  type="number"
                  min="1"
                  max="100"
                  label={gettext("% cumulé")}
                />
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">
                    {if @editing_tranche, do: gettext("Enregistrer"), else: gettext("Ajouter")}
                  </button>
                  <button
                    :if={@editing_tranche}
                    type="button"
                    phx-click="cancel_tranche"
                    class="btn btn-ghost btn-sm"
                  >
                    {gettext("Annuler")}
                  </button>
                </div>
                <p :if={@tranche_error} class="text-sm text-error sm:col-span-4">{@tranche_error}</p>
              </.form>
            </div>
          </.fee_step>
        </ol>

        <section :if={@arrears != []} id="arrears" class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("Reporter les reliquats de l'année précédente")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "Décochez les élèves dont l'école ne réclame pas la dette. Un élève non réinscrit ne peut pas être reporté."
            )}
          </p>
          <form id="arrears-form" phx-submit="carry_arrears" class="space-y-3">
            <ul class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
              <li
                :for={c <- @arrears}
                class={["flex items-center gap-3 px-4 py-2", !c.enrollment && "opacity-60"]}
              >
                <input
                  :if={c.enrollment}
                  type="checkbox"
                  name="enrollment_ids[]"
                  value={c.enrollment.id}
                  checked
                  class="checkbox checkbox-sm"
                  aria-label={c.student.full_name}
                />
                <span :if={!c.enrollment} class="size-4"></span>
                <span class="flex-1">{c.student.full_name}</span>
                <span :if={!c.enrollment} class="text-xs text-base-content/70">{gettext(
                  "non réinscrit"
                )}</span>
                <span class="ta-num">{Money.format_fcfa(c.amount)}</span>
              </li>
            </ul>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Reporter")}</button>
          </form>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
