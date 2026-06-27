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
     |> assign(:form, to_form(%{}, as: :log))}
  end

  def handle_event("save", %{"log" => p}, socket) do
    case Academics.log_teaching(socket.assigns.ws, %{
           progression_entry_id: p["progression_entry_id"],
           date: p["date"],
           content_taught: p["content_taught"],
           hours: Decimal.new(blank_to(p["hours"], "1")),
           status: String.to_existing_atom(p["status"]),
           homework: blank_to(p["homework"], nil),
           note: blank_to(p["note"], nil)
         }) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, gettext("Logged")) |> push_navigate(to: ~p"/teacher")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not log"))}
    end
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-log" class="p-4 max-w-md mx-auto space-y-3">
        <h1 class="text-xl font-semibold">{gettext("Log what you taught")}</h1>
        <.form for={@form} id="log-form" phx-submit="save" class="space-y-3">
          <.input
            type="select"
            field={@form[:progression_entry_id]}
            label={gettext("Lesson")}
            options={for e <- @entries, do: {"#{e.module} · #{e.lesson_title}", e.id}}
          />
          <.input type="date" field={@form[:date]} label={gettext("Date")} />
          <.input field={@form[:content_taught]} label={gettext("What was taught")} />
          <.input type="number" field={@form[:hours]} label={gettext("Hours")} value="1" />
          <.input
            type="select"
            field={@form[:status]}
            label={gettext("Status")}
            options={[{gettext("Done"), "done"}, {gettext("Partial"), "partial"}]}
          />
          <.input field={@form[:homework]} label={gettext("Homework (optional)")} />
          <.input field={@form[:note]} label={gettext("Note (optional)")} />
          <.button id="log-submit" type="submit" class="btn btn-primary w-full">
            {gettext("Save")}
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
