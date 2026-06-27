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
    socket
    |> assign(:plan, plan)
    |> assign(:entries, Academics.list_progression_entries(plan))
    |> assign(:entry_form, to_form(%{}, as: :entry))
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="fiche-builder" class="space-y-6">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <p class="ta-eyebrow">{gettext("Fiche de progression")}</p>
            <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{@plan.title}</h1>
          </div>
          <.button id="duplicate-plan" phx-click="duplicate-plan" class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-document-duplicate" class="size-4" />
            {gettext("Duplicate")}
          </.button>
        </header>

        <ul id="fiche-entries" class="space-y-2">
          <li
            :for={e <- @entries}
            id={"entry-#{e.id}"}
            class="ta-leaf flex flex-row items-center justify-between gap-3"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-display font-semibold">{e.lesson_title}</span>
                <span class="badge badge-soft badge-sm">{e.entry_type}</span>
              </div>
              <div class="mt-0.5 text-sm text-base-content/65">
                {e.module} <span class="text-base-content/40">·</span>
                <span class="ta-num">{e.planned_hours}h</span>
              </div>
            </div>
            <.button
              phx-click="delete-entry"
              phx-value-id={e.id}
              class="btn btn-ghost btn-xs text-error"
            >
              <.icon name="hero-trash" class="size-4" />
              <span class="sr-only">{gettext("Delete")}</span>
            </.button>
          </li>
          <li :if={@entries == []} class="ta-leaf text-sm text-base-content/60">
            {gettext("No entries yet — add your first lesson below.")}
          </li>
        </ul>

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
