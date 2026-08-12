defmodule TeacherAssistantWeb.Teacher.FicheLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
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
        {:ok, _} = Academics.create_module(socket.assigns.plan, %{title: t})
        {:noreply, assign_modules(socket, socket.assigns.plan)}
    end
  end

  def handle_event("rename-module", %{"id" => id, "title" => title}, socket) do
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

    with {:ok, module} <- ws && Academics.fetch_owned_module(module_id, ws),
         {:ok, _} <-
           Academics.add_progression_entry(module, %{
             lesson_title: p["lesson_title"],
             planned_hours: Decimal.new(blank_to(p["planned_hours"], "1")),
             entry_type: String.to_existing_atom(p["entry_type"])
           }) do
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

    socket
    |> assign(:plan, plan)
    |> assign(:ctx, ctx)
    |> assign(:modules, modules)
    |> assign(:prepared, prepared)
    |> assign(:module_form, to_form(%{}, as: :module))
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
                <span class="ta-eyebrow">{m.title}</span>
                <span class="ta-num text-sm text-base-content/60">
                  {Decimal.to_string(module_hours(m))}h
                </span>
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
                  <span>
                    <span class="font-display font-semibold">{e.lesson_title}</span>
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
