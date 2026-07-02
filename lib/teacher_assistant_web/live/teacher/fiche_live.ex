defmodule TeacherAssistantWeb.Teacher.FicheLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Reference

  def mount(%{"id" => id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_plan(id, ws) do
      {:ok, plan} ->
        {:ok, assign_entries(socket, plan)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Plan not found"))
         |> push_navigate(to: ~p"/teacher")}
    end
  end

  def handle_event("add-entry", %{"entry" => p}, socket) do
    case Academics.add_progression_entry(socket.assigns.plan, %{
           module: p["module"],
           lesson_title: p["lesson_title"],
           planned_hours: Decimal.new(blank_to(p["planned_hours"], "1")),
           entry_type: String.to_existing_atom(p["entry_type"])
         }) do
      {:ok, _} -> {:noreply, assign_entries(socket, socket.assigns.plan)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not add entry"))}
    end
  end

  def handle_event("delete-entry", %{"id" => id}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_entry(id, ws) do
      {:ok, entry} ->
        case Academics.delete_progression_entry(entry) do
          :ok -> {:noreply, assign_entries(socket, socket.assigns.plan)}
          {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not delete entry"))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete entry"))}
    end
  end

  def handle_event("duplicate-plan", _params, socket) do
    case Academics.duplicate_progression_plan(socket.assigns.plan, %{}) do
      {:ok, copy} -> {:noreply, push_navigate(socket, to: ~p"/teacher/plans/#{copy.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not duplicate plan"))}
    end
  end

  defp assign_entries(socket, plan) do
    ctx =
      case Academics.get_teaching_context(plan.teaching_context_id) do
        {:ok, ctx} -> ctx
        _ -> nil
      end

    entries = Academics.list_progression_entries(plan)

    prepared =
      entries
      |> Enum.filter(fn e -> Academics.get_lesson_plan_for_entry(e.id) end)
      |> MapSet.new(& &1.id)

    socket
    |> assign(:plan, plan)
    |> assign(:ctx, ctx)
    |> assign(:entries, entries)
    |> assign(:prepared, prepared)
    |> assign(:entry_form, to_form(%{}, as: :entry))
  end

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
            value={Decimal.to_string(hours_total(@entries))}
            suffix="h"
          />
          <p
            :if={@ctx && weeks_estimate(hours_total(@entries), @ctx.weekly_hours)}
            class="text-sm text-base-content/60"
          >
            {gettext("≈ %{weeks} weeks at %{hours} h/week",
              weeks: weeks_estimate(hours_total(@entries), @ctx.weekly_hours),
              hours: @ctx.weekly_hours
            )}
          </p>
        </div>

        <table
          :if={@entries != []}
          id="fiche-entries"
          class="w-full border-separate border-spacing-y-1"
        >
          <caption class="sr-only">{gettext("Progression entries")}</caption>
          <thead class="hidden md:table-header-group">
            <tr class="text-left">
              <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Module")}</th>
              <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Leçon")}</th>
              <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Type")}</th>
              <th scope="col" class="ta-eyebrow px-3 pb-1 text-right">{gettext("Heures")}</th>
              <th scope="col" class="px-3 pb-1"><span class="sr-only">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody class="block space-y-2 md:table-row-group">
            <tr :for={e <- @entries} id={"entry-#{e.id}"} class="ta-leaf block md:table-row">
              <td class="hidden text-sm text-base-content/65 md:table-cell md:px-3 md:py-2">
                {e.module}
              </td>
              <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
                <span>
                  <span class="font-display font-semibold">{e.lesson_title}</span>
                  <span class="mt-0.5 block text-sm text-base-content/65 md:hidden">
                    {e.module} <span class="text-base-content/40">·</span>
                    <span class="ta-num">{e.planned_hours}h</span>
                    <span class="badge badge-soft badge-sm ml-1">{e.entry_type}</span>
                  </span>
                </span>
                <div class="flex items-center gap-1 md:hidden">
                  <.link
                    id={"entry-prepare-mobile-#{e.id}"}
                    navigate={~p"/teacher/entries/#{e.id}/fiche"}
                    class="btn btn-ghost btn-xs gap-1"
                  >
                    <.icon name="hero-document-text" class="size-3.5" />
                    {gettext("Préparer")}
                    <span :if={MapSet.member?(@prepared, e.id)} id={"entry-prepared-mobile-#{e.id}"}>
                      <.icon name="hero-check-circle" class="size-3.5 text-success" />
                    </span>
                  </.link>
                  <.button
                    phx-click="delete-entry"
                    phx-value-id={e.id}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-trash" class="size-4" />
                    <span class="sr-only">{gettext("Delete")}</span>
                  </.button>
                </div>
              </td>
              <td class="hidden md:table-cell md:px-3 md:py-2">
                <span class="badge badge-soft badge-sm">{e.entry_type}</span>
              </td>
              <td class="ta-num hidden text-right md:table-cell md:px-3 md:py-2">
                {e.planned_hours}h
              </td>
              <td class="hidden text-right md:table-cell md:px-3 md:py-2">
                <div class="flex items-center justify-end gap-1">
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
              </td>
            </tr>
          </tbody>
        </table>
        <.empty_state
          :if={@entries == []}
          icon="hero-document-text"
          title={gettext("No entries yet — add your first lesson below.")}
        />

        <.form
          for={@entry_form}
          id="add-entry-form"
          phx-submit="add-entry"
          class="card bg-base-100 p-4 space-y-2"
        >
          <p class="ta-eyebrow">{gettext("Add entry")}</p>
          <.input field={@entry_form[:module]} label={gettext("Module")} />
          <.input field={@entry_form[:lesson_title]} label={gettext("Lesson")} />
          <div class="grid gap-2 sm:grid-cols-2">
            <.input
              type="number"
              field={@entry_form[:planned_hours]}
              label={gettext("Hours")}
              value="1"
            />
            <.input
              type="select"
              field={@entry_form[:entry_type]}
              label={gettext("Type")}
              options={for t <- Reference.entry_types(), do: {t.fr, t.key}}
            />
          </div>
          <.button id="add-entry-submit" type="submit" class="btn btn-primary w-full gap-2">
            <.icon name="hero-plus" class="size-4" />
            {gettext("Add entry")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
