defmodule TeacherAssistantWeb.Teacher.LogLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(_params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace
    plans = if ws, do: Academics.list_progression_plans(ws), else: []
    entries = Enum.flat_map(plans, &Academics.list_progression_entries/1)

    {:ok,
     socket
     |> assign(:ws, ws)
     |> assign(:entries, entries)
     |> assign(:recent, (ws && Academics.list_recent_logs(ws, 5)) || [])
     |> assign(:form, to_form(%{"hours" => "1"}, as: :log))}
  end

  def handle_event("validate", %{"log" => p}, socket) do
    errors =
      case Decimal.parse(p["hours"] || "") do
        {_d, ""} -> []
        _ -> [hours: {gettext("Enter hours like 1 or 1.5"), []}]
      end

    {:noreply, assign(socket, :form, to_form(p, as: :log, errors: errors, action: :validate))}
  end

  def handle_event("save", %{"log" => p}, socket) do
    ws = socket.assigns.ws

    with {:ok, _entry} <- ws && Academics.fetch_owned_entry(p["progression_entry_id"], ws),
         {:ok, _} <-
           Academics.log_teaching(ws, %{
             progression_entry_id: p["progression_entry_id"],
             date: p["date"],
             content_taught: p["content_taught"],
             hours: Decimal.new(blank_to(p["hours"], "1")),
             status: String.to_existing_atom(p["status"]),
             homework: blank_to(p["homework"], nil),
             note: blank_to(p["note"], nil)
           }) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Logged"))
       |> assign(:recent, Academics.list_recent_logs(ws, 5))
       |> assign(:form, to_form(%{"hours" => "1"}, as: :log))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not log"))}
    end
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-log" class="mx-auto max-w-md space-y-5">
        <.page_header
          eyebrow={gettext("Cahier de textes")}
          title={gettext("Log what you taught")}
        />
        <.form
          for={@form}
          id="log-form"
          phx-change="validate"
          phx-submit="save"
          class="ta-leaf space-y-2"
        >
          <.input
            type="select"
            field={@form[:progression_entry_id]}
            label={gettext("Lesson")}
            options={for e <- @entries, do: {"#{e.progression_module.title} · #{e.lesson_title}", e.id}}
          />
          <div class="grid gap-2 sm:grid-cols-2">
            <.input type="date" field={@form[:date]} label={gettext("Date")} />
            <.input type="number" field={@form[:hours]} label={gettext("Hours")} inputmode="decimal" />
          </div>
          <.input field={@form[:content_taught]} label={gettext("What was taught")} />
          <.input
            type="select"
            field={@form[:status]}
            label={gettext("Status")}
            options={[{gettext("Done"), "done"}, {gettext("Partial"), "partial"}]}
          />
          <.input field={@form[:homework]} label={gettext("Homework (optional)")} />
          <.input field={@form[:note]} label={gettext("Note (optional)")} />
          <.button id="log-submit" type="submit" class="btn btn-primary w-full gap-2">
            <.icon name="hero-check" class="size-4" />
            {gettext("Save")}
          </.button>
        </.form>

        <div :if={@recent != []} class="space-y-2">
          <h2 class="ta-eyebrow">{gettext("Recently logged")}</h2>
          <ul id="log-recent" class="space-y-1">
            <li
              :for={l <- @recent}
              id={"log-recent-#{l.id}"}
              class="ta-leaf flex items-baseline justify-between gap-2 text-sm"
            >
              <span class="flex-1 truncate">{l.content_taught}</span>
              <span class="ta-num shrink-0 text-base-content/60">{l.date} · {l.hours}h</span>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
