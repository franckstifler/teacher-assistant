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
      <section id="fiche-builder" class="p-4 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">{@plan.title}</h1>
          <.button id="duplicate-plan" phx-click="duplicate-plan" class="btn btn-ghost btn-sm">
            {gettext("Duplicate")}
          </.button>
        </div>

        <ul id="fiche-entries" class="space-y-2">
          <li
            :for={e <- @entries}
            id={"entry-#{e.id}"}
            class="card bg-base-100 shadow p-3 flex flex-row justify-between items-center"
          >
            <div>
              <div class="font-medium">{e.lesson_title}</div>
              <div class="text-sm opacity-70">{e.module} · {e.planned_hours}h · {e.entry_type}</div>
            </div>
            <.button phx-click="delete-entry" phx-value-id={e.id} class="btn btn-ghost btn-xs">
              {gettext("Delete")}
            </.button>
          </li>
        </ul>

        <.form
          for={@entry_form}
          id="add-entry-form"
          phx-submit="add-entry"
          class="card bg-base-200 p-3 space-y-2"
        >
          <.input field={@entry_form[:module]} label={gettext("Module")} />
          <.input field={@entry_form[:lesson_title]} label={gettext("Lesson")} />
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
          <.button id="add-entry-submit" type="submit" class="btn btn-primary">
            {gettext("Add entry")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
