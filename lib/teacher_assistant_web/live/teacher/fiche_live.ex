defmodule TeacherAssistantWeb.Teacher.FicheLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Quota
  alias TeacherAssistant.Academics.Reference

  def mount(%{"id" => id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_plan(id, ws) do
      {:ok, plan} ->
        {:ok, assign_modules(socket, plan)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Plan not found"))
         |> push_navigate(to: ~p"/teacher")}
    end
  end

  def handle_event("add-module", %{"module" => %{"title" => title}}, socket) do
    case title && String.trim(title) do
      t when t in [nil, ""] ->
        {:noreply, socket}

      t ->
        case Academics.create_module(socket.assigns.plan, %{title: t}) do
          {:ok, _} ->
            {:noreply, assign_modules(socket, socket.assigns.plan)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not add module"))}
        end
    end
  end

  def handle_event("rename-module", %{"module_id" => id, "title" => title}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         {:ok, _} <- Academics.rename_module(m, title) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not rename module"))}
    end
  end

  def handle_event("delete-module", %{"id" => id}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         :ok <- Academics.delete_module(m) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      {:error, :default_bucket} ->
        {:noreply, put_flash(socket, :error, gettext("The default section cannot be deleted"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete module"))}
    end
  end

  def handle_event("add-entry", %{"module_id" => module_id, "entry" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, entry_attrs} <- entry_attrs_from_params(p),
         {:ok, module} <- ws && Academics.fetch_owned_module(module_id, ws),
         {:ok, _} <- Academics.add_progression_entry(module, entry_attrs) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not add entry"))}
    end
  end

  def handle_event("delete-entry", %{"id" => id}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_entry(id, ws) do
      {:ok, entry} ->
        case Academics.delete_progression_entry(entry) do
          :ok -> {:noreply, assign_modules(socket, socket.assigns.plan)}
          {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not delete entry"))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete entry"))}
    end
  end

  def handle_event("apply-layout", %{"layout" => layout}, socket) do
    case Academics.apply_layout(socket.assigns.plan, layout) do
      {:ok, :applied} -> {:noreply, assign_modules(socket, socket.assigns.plan)}
      {:error, _} -> {:noreply, assign_modules(socket, socket.assigns.plan)}
    end
  end

  def handle_event("duplicate-plan", _params, socket) do
    case Academics.duplicate_progression_plan(socket.assigns.plan, %{}) do
      {:ok, copy} -> {:noreply, push_navigate(socket, to: ~p"/teacher/plans/#{copy.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not duplicate plan"))}
    end
  end

  def handle_event("save-targets", %{"targets" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace
    ctx = socket.assigns.ctx

    attrs = %{
      annual_hours: parse_decimal(p["annual_hours"]),
      target_module_count: parse_int(p["target_module_count"]),
      target_lesson_count: parse_int(p["target_lesson_count"])
    }

    case ws && ctx && Academics.update_teaching_context(ctx.id, ws, attrs) do
      {:ok, _} -> {:noreply, assign_modules(socket, socket.assigns.plan)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not save targets"))}
    end
  end

  def handle_event("save-module-credit", %{"module_id" => id, "credit_hours" => raw}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         {:ok, _} <- Academics.update_module_credit(m, parse_decimal(raw)) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not save credit"))}
    end
  end

  def handle_event("toggle-complete", %{"id" => id}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, e} <- ws && Academics.fetch_owned_entry(id, ws),
         {:ok, _} <- Academics.set_entry_completed(e, not e.completed?) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not update lesson"))}
    end
  end

  def handle_event("assign-module-sequence", %{"module_id" => id, "sequence_id" => raw}, socket) do
    ws = socket.assigns.current_scope.current_workspace
    sequence_id = if raw in [nil, ""], do: nil, else: raw

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         {:ok, _} <- Academics.assign_module_sequence(m, sequence_id) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not assign sequence"))}
    end
  end

  defp assign_modules(socket, plan) do
    ctx =
      case Academics.get_teaching_context(plan.teaching_context_id) do
        {:ok, ctx} -> ctx
        _ -> nil
      end

    modules = Academics.list_progression_modules(plan)

    prepared =
      modules
      |> Enum.flat_map(& &1.entries)
      |> Enum.filter(fn e -> Academics.get_lesson_plan_for_entry(e.id) end)
      |> MapSet.new(& &1.id)

    ws = socket.assigns.current_scope.current_workspace
    year = ws && Academics.current_academic_year(ws)
    sequences = (year && Academics.list_sequences(year)) || []

    socket
    |> assign(:plan, plan)
    |> assign(:ctx, ctx)
    |> assign(:modules, modules)
    |> assign(:prepared, prepared)
    |> assign(:sequences, sequences)
    |> assign(:module_form, to_form(%{}, as: :module))
    |> assign(:quota, Quota.summarize(ctx, modules))
    |> assign(:targets_form, to_form(%{}, as: :targets))
  end

  defp module_hours(%{entries: entries}),
    do: Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.planned_hours) end)

  defp all_entries(modules), do: Enum.flat_map(modules, & &1.entries)

  defp hours_total(entries) do
    Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.planned_hours) end)
  end

  defp weeks_estimate(_total, nil), do: nil

  defp weeks_estimate(total, weekly_hours) when weekly_hours > 0 do
    total
    |> Decimal.div(Decimal.new(weekly_hours))
    |> Decimal.round(0, :ceiling)
    |> Decimal.to_string()
  end

  defp weeks_estimate(_total, _), do: nil

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  # ratio helpers for the quota header — nil-safe, advisory only.
  defp ratio_pct(nil), do: nil
  defp ratio_pct(r) when is_number(r), do: round(r * 100)

  defp count_ratio(_n, nil), do: nil
  defp count_ratio(_n, 0), do: nil
  defp count_ratio(n, t) when is_integer(t) and t > 0, do: n / t

  defp ratio_accent(nil), do: nil
  defp ratio_accent(r) when r > 1.0, do: "text-warning"
  defp ratio_accent(r) when r < 0.5, do: "text-base-content/60"
  defp ratio_accent(_r), do: "text-success"

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :target, :string, default: nil
  attr :suffix, :string, default: nil
  attr :ratio, :any, default: nil

  defp quota_stat(assigns) do
    ~H"""
    <div class="ta-leaf">
      <p class="ta-eyebrow">{@label}</p>
      <p class={["ta-num mt-1 text-2xl font-semibold leading-none", ratio_accent(@ratio)]}>
        {@value}<span :if={@target} class="text-base font-normal text-base-content/55">
          / {@target}{@suffix}
        </span><span
          :if={!@target && @suffix}
          class="text-base font-normal text-base-content/55"
        >
          {@suffix}
        </span>
      </p>
      <progress
        :if={@target}
        class={[
          "progress w-full mt-1",
          if(ratio_accent(@ratio) == "text-warning", do: "progress-warning", else: "progress-primary")
        ]}
        value={ratio_pct(@ratio) || 0}
        max="100"
      >
      </progress>
    </div>
    """
  end

  # Validates/parses the raw "add-entry" form params before they ever reach
  # Ash. Decimal.new/1 and String.to_existing_atom/1 both raise on malformed
  # input, which is not caught by a `with`/`else` clause — so we guard here
  # and return {:error, _} instead of crashing the LiveView.
  defp entry_attrs_from_params(p) do
    with {:ok, entry_type} <- parse_entry_type(p["entry_type"]),
         {:ok, planned_hours} <- parse_planned_hours(p["planned_hours"]) do
      {:ok,
       %{
         lesson_title: p["lesson_title"],
         planned_hours: planned_hours,
         entry_type: entry_type
       }}
    end
  end

  defp parse_entry_type(key) when is_binary(key) do
    valid_keys = Enum.map(Reference.entry_type_keys(), &Atom.to_string/1)

    if key in valid_keys do
      {:ok, String.to_existing_atom(key)}
    else
      {:error, :invalid_entry_type}
    end
  end

  defp parse_entry_type(_), do: {:error, :invalid_entry_type}

  defp parse_planned_hours(raw) do
    case Decimal.parse(blank_to(raw, "1")) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, :invalid_planned_hours}
    end
  end

  defp entry_form_for(m), do: to_form(%{}, as: :entry, id: "entry-form-#{m.id}")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="fiche-builder" class="space-y-6">
        <.page_header eyebrow={gettext("Fiche de progression")} title={@plan.title}>
          <:actions>
            <.button
              id="duplicate-plan"
              phx-click="duplicate-plan"
              class="btn btn-ghost btn-sm gap-2"
            >
              <.icon name="hero-document-duplicate" class="size-4" />
              {gettext("Duplicate")}
            </.button>
          </:actions>
        </.page_header>

        <div id="fiche-hours-total" class="flex items-center gap-3">
          <.stat
            label={gettext("Planned hours")}
            value={Decimal.to_string(hours_total(all_entries(@modules)))}
            suffix="h"
          />
          <p
            :if={@ctx && weeks_estimate(hours_total(all_entries(@modules)), @ctx.weekly_hours)}
            class="text-sm text-base-content/60"
          >
            {gettext("≈ %{weeks} weeks at %{hours} h/week",
              weeks: weeks_estimate(hours_total(all_entries(@modules)), @ctx.weekly_hours),
              hours: @ctx.weekly_hours
            )}
          </p>
        </div>

        <div id="quota-header" class="grid gap-3 sm:grid-cols-3">
          <.quota_stat
            label={gettext("Heures")}
            value={Decimal.to_string(@quota.planned_hours)}
            target={@quota.annual_hours && Decimal.to_string(@quota.annual_hours)}
            suffix="h"
            ratio={@quota.hours_ratio}
          />
          <.quota_stat
            label={gettext("Modules")}
            value={Integer.to_string(@quota.module_count)}
            target={@quota.target_module_count && Integer.to_string(@quota.target_module_count)}
            ratio={count_ratio(@quota.module_count, @quota.target_module_count)}
          />
          <.quota_stat
            label={gettext("Leçons")}
            value={Integer.to_string(@quota.lesson_count)}
            target={@quota.target_lesson_count && Integer.to_string(@quota.target_lesson_count)}
            ratio={count_ratio(@quota.lesson_count, @quota.target_lesson_count)}
          />
        </div>

        <.form
          for={@targets_form}
          id="targets-form"
          phx-submit="save-targets"
          class="flex flex-wrap items-end gap-2"
        >
          <.input
            type="number"
            name="targets[annual_hours]"
            value={@quota.annual_hours && Decimal.to_string(@quota.annual_hours)}
            label={gettext("Horaire annuel")}
            step="0.5"
          />
          <.input
            type="number"
            name="targets[target_module_count]"
            value={@quota.target_module_count}
            label={gettext("Cible modules")}
          />
          <.input
            type="number"
            name="targets[target_lesson_count]"
            value={@quota.target_lesson_count}
            label={gettext("Cible leçons")}
          />
          <.button type="submit" class="btn btn-ghost btn-sm">{gettext("Save targets")}</.button>
        </.form>

        <.empty_state
          :if={all_entries(@modules) == []}
          icon="hero-document-text"
          title={gettext("No entries yet — add your first lesson below.")}
        />

        <div id="fiche-modules" phx-hook="ModuleLayout" class="space-y-4">
          <span data-sr-live aria-live="polite" class="sr-only"></span>
          <article
            :for={m <- @modules}
            id={"module-#{m.id}"}
            data-module-id={m.id}
            class="card bg-base-100 p-4 space-y-2"
          >
            <header class="flex items-center justify-between gap-2">
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  data-module-handle
                  class="btn btn-ghost btn-xs cursor-grab"
                  aria-label={gettext("Reorder module")}
                >
                  <.icon name="hero-bars-3" class="size-4" />
                </button>
                <form
                  id={"rename-module-form-#{m.id}"}
                  phx-submit="rename-module"
                  class="flex items-center gap-1"
                >
                  <input type="hidden" name="module_id" value={m.id} />
                  <input
                    type="text"
                    name="title"
                    value={m.title}
                    class="input input-xs input-ghost ta-eyebrow w-40"
                    aria-label={gettext("Module title")}
                  />
                  <button
                    type="submit"
                    class="btn btn-ghost btn-xs"
                    aria-label={gettext("Rename module")}
                  >
                    <.icon name="hero-check" class="size-3.5" />
                  </button>
                </form>
                <span class="ta-num text-sm text-base-content/60">
                  {Decimal.to_string(module_hours(m))}h
                </span>
                <span
                  :if={not m.default? and m.credit_hours}
                  class="ta-num text-sm text-base-content/60"
                >
                  / {Decimal.to_string(m.credit_hours)}h
                </span>
                <.form
                  :if={not m.default?}
                  for={to_form(%{}, as: :credit)}
                  id={"module-credit-form-#{m.id}"}
                  phx-submit="save-module-credit"
                  class="flex items-end gap-1"
                >
                  <input type="hidden" name="module_id" value={m.id} />
                  <.input
                    type="number"
                    name="credit_hours"
                    value={m.credit_hours && Decimal.to_string(m.credit_hours)}
                    step="0.5"
                    label={gettext("Crédit h")}
                  />
                  <.button type="submit" class="btn btn-ghost btn-xs">{gettext("Save")}</.button>
                </.form>
                <.form
                  for={to_form(%{}, as: :seq)}
                  id={"seq-form-#{m.id}"}
                  phx-change="assign-module-sequence"
                  class="flex items-center gap-1"
                >
                  <input type="hidden" name="module_id" value={m.id} />
                  <select
                    name="sequence_id"
                    class="select select-sm select-ghost"
                    aria-label={gettext("Assign sequence")}
                  >
                    <option value="" selected={is_nil(m.sequence_id)}>
                      {gettext("Sans séquence")}
                    </option>
                    <option :for={s <- @sequences} value={s.id} selected={m.sequence_id == s.id}>
                      {gettext("Séq %{n}", n: s.number)}
                    </option>
                  </select>
                </.form>
              </div>
              <.button
                :if={not m.default?}
                id={"module-delete-#{m.id}"}
                phx-click="delete-module"
                phx-value-id={m.id}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-trash" class="size-4" />
                <span class="sr-only">{gettext("Delete module")}</span>
              </.button>
            </header>

            <ul data-entries class="space-y-1">
              <li
                :for={e <- m.entries}
                id={"entry-#{e.id}"}
                data-entry-id={e.id}
                class="ta-leaf flex items-center justify-between gap-2 px-2 py-1.5"
              >
                <div class="flex items-center gap-1">
                  <button
                    type="button"
                    data-entry-handle
                    class="btn btn-ghost btn-xs cursor-grab"
                    aria-label={gettext("Reorder lesson")}
                  >
                    <.icon name="hero-bars-2" class="size-3.5" />
                  </button>
                  <input
                    id={"entry-complete-#{e.id}"}
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={e.completed?}
                    phx-click="toggle-complete"
                    phx-value-id={e.id}
                    aria-label={gettext("Mark lesson done")}
                  />
                  <span>
                    <span class={[
                      "font-display font-semibold",
                      e.completed? && "line-through text-base-content/50"
                    ]}>
                      {e.lesson_title}
                    </span>
                    <span class="badge badge-soft badge-sm ml-1">{e.entry_type}</span>
                    <span class="ta-num ml-1 text-sm text-base-content/60">{e.planned_hours}h</span>
                  </span>
                </div>
                <div class="flex items-center gap-1">
                  <.link
                    id={"entry-prepare-#{e.id}"}
                    navigate={~p"/teacher/entries/#{e.id}/fiche"}
                    class="btn btn-ghost btn-xs gap-1"
                  >
                    <.icon name="hero-document-text" class="size-3.5" />
                    {gettext("Préparer")}
                    <span :if={MapSet.member?(@prepared, e.id)} id={"entry-prepared-#{e.id}"}>
                      <.icon name="hero-check-circle" class="size-3.5 text-success" />
                    </span>
                  </.link>
                  <.button
                    id={"entry-delete-#{e.id}"}
                    phx-click="delete-entry"
                    phx-value-id={e.id}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-trash" class="size-4" />
                    <span class="sr-only">{gettext("Delete")}</span>
                  </.button>
                </div>
              </li>
            </ul>

            <.form
              :let={f}
              for={entry_form_for(m)}
              id={"add-entry-form-#{m.id}"}
              phx-submit="add-entry"
              class="flex flex-wrap items-end gap-2"
            >
              <input type="hidden" name="module_id" value={m.id} />
              <.input field={f[:lesson_title]} label={gettext("Lesson")} />
              <.input type="number" field={f[:planned_hours]} label={gettext("Hours")} value="1" />
              <.input
                type="select"
                field={f[:entry_type]}
                label={gettext("Type")}
                options={for t <- Reference.entry_types(), do: {t.fr, t.key}}
              />
              <.button type="submit" class="btn btn-primary btn-sm gap-1">
                <.icon name="hero-plus" class="size-4" />
                {gettext("Add")}
              </.button>
            </.form>
          </article>
        </div>

        <.form
          for={@module_form}
          id="add-module-form"
          phx-submit="add-module"
          class="card bg-base-100 p-4 flex flex-wrap items-end gap-2"
        >
          <.input field={@module_form[:title]} label={gettext("New module")} />
          <.button type="submit" class="btn btn-primary btn-sm gap-1">
            <.icon name="hero-plus" class="size-4" />
            {gettext("Add module")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
