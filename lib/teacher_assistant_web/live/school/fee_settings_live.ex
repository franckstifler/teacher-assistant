defmodule TeacherAssistantWeb.School.FeeSettingsLive do
  @moduledoc """
  Paramètres des frais (Fees 1, rule 25): the year's fee types in payment order, the
  amounts per class, the cumulative tranches, copying last year, and carrying last
  year's unpaid fees. Fees axis (Proviseur, Censeur, Intendant).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, Fees, Organization}
  alias TeacherAssistant.Academics.SchoolTemplates
  alias TeacherAssistantWeb.Money

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

  defp load(socket) do
    %{year: year} = socket.assigns
    types = Fees.list_fee_types(scope(socket), year)

    assign(socket,
      types: types,
      regular: Enum.filter(types, &(&1.kind == :regular and &1.active?)),
      classes:
        scope(socket)
        |> Enrollment.list_class_groups(year)
        |> Enum.sort_by(&SchoolTemplates.class_sort_key/1),
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

  def handle_event("create_default_types", _params, socket),
    do: socket |> result(Fees.create_default_fee_types(scope(socket), socket.assigns.year))

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
    with %{} = type <- find_type(socket, id) do
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
    else
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

  def handle_event("set_level", %{"cg" => cg_id, "type" => type_id}, socket) do
    with %{} = cg <- find_class(socket, cg_id),
         %{} = type <- find_type(socket, type_id) do
      amount = Map.get(socket.assigns.grid, {cg.id, type.id}, 0)
      result(socket, Fees.set_level_fee(scope(socket), socket.assigns.year, cg, type, amount))
    else
      _ -> {:noreply, socket}
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

  defp tranche_error(socket, params),
    do:
      assign(socket,
        tranche_form: to_form(params, as: :tranche),
        tranche_error: gettext("Indiquez une date et un pourcentage entre 1 et 100.")
      )

  defp find_type(socket, id), do: Enum.find(socket.assigns.types, &(&1.id == id))
  defp find_class(socket, id), do: Enum.find(socket.assigns.classes, &(&1.id == id))

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
      <section id="fee-settings" class="space-y-8">
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

        <section id="fee-types" class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("Types de frais")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "L'ordre est l'ordre de paiement : une somme versée règle d'abord le premier frais."
            )}
          </p>

          <div :if={@types == []} class="flex flex-wrap gap-2">
            <button
              id="create-default-types"
              type="button"
              phx-click="create_default_types"
              class="btn btn-primary btn-sm"
            >
              {gettext("Créer Frais exigibles et PTA")}
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

          <ol
            :if={@types != []}
            class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100"
          >
            <li
              :for={{t, i} <- Enum.with_index(@types)}
              id={"fee-type-#{t.id}"}
              class={["flex flex-wrap items-center gap-2 px-4 py-2", !t.active? && "opacity-60"]}
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

          <.form
            for={@type_form}
            id="new-fee-type-form"
            phx-change="change_type"
            phx-submit="add_type"
            class="flex flex-wrap items-end gap-2"
          >
            <div class="min-w-56 flex-1">
              <.input
                field={@type_form[:name]}
                label={gettext("Nouveau frais")}
                placeholder="Frais informatique"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter")}</button>
          </.form>
          <p :if={@type_error} class="text-sm text-error">{@type_error}</p>
        </section>

        <section :if={@regular != []} id="fee-grid" class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("Montants par classe")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext("Laissez vide ou 0 pour une classe qui ne paie pas ce frais.")}
          </p>
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th class="sticky left-0 z-10 bg-base-100">{gettext("Classe")}</th>
                  <th :for={t <- @regular}>{t.name}</th>
                  <th class="text-right">{gettext("Total")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={cg <- @classes}>
                  <td class="sticky left-0 z-10 whitespace-nowrap bg-base-100 font-semibold">
                    {cg.label}
                  </td>
                  <td :for={t <- @regular} class="min-w-36">
                    <div class="flex items-center gap-1">
                      <form id={"fee-#{cg.id}-#{t.id}"} phx-change="set_fee">
                        <input type="hidden" name="cg" value={cg.id} />
                        <input type="hidden" name="type" value={t.id} />
                        <input
                          name="amount"
                          inputmode="numeric"
                          phx-debounce="blur"
                          value={Map.get(@grid, {cg.id, t.id})}
                          aria-label={"#{cg.label} · #{t.name}"}
                          class="input input-sm w-28 text-right ta-num"
                        />
                      </form>
                      <button
                        :if={Enum.count(@classes, &(&1.level == cg.level)) > 1}
                        id={"level-#{cg.id}-#{t.id}"}
                        type="button"
                        phx-click="set_level"
                        phx-value-cg={cg.id}
                        phx-value-type={t.id}
                        title={gettext("Même montant pour tout le niveau")}
                        aria-label={gettext("Même montant pour tout le niveau")}
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-arrows-up-down" class="size-4" />
                      </button>
                    </div>
                  </td>
                  <td class="ta-num whitespace-nowrap text-right">
                    {Money.format_fcfa(class_total(@grid, @regular, cg))}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section id="tranches" class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("Tranches")}</h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "Chaque tranche dit quelle part du total chaque élève doit avoir payée à sa date (cumulée)."
            )}
          </p>
          <div
            :if={@tranches != []}
            class="overflow-x-auto rounded-box border border-base-300 bg-base-100"
          >
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
            class="grid items-end gap-2 rounded-box border border-base-300 bg-base-100 p-4 sm:grid-cols-4"
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
        </section>

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
