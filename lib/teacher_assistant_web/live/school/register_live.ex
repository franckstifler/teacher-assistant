defmodule TeacherAssistantWeb.School.RegisterLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    date = parse_date(params["date"])

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- authorized?(scope, cg) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         date: date,
         can_edit?: Permissions.conduct_manager?(scope)
       )
       |> load_register()}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp parse_date(nil), do: Date.utc_today()

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  defp authorized?(scope, cg) do
    Permissions.conduct_manager?(scope) or Permissions.admin_or_form_master?(scope, cg)
  end

  defp load_register(socket) do
    register = Attendance.class_register(socket.assigns.cg, socket.assigns.date)
    scope = socket.assigns.current_scope

    sequence =
      case scope.current_academic_year do
        nil -> nil
        year -> Academics.current_sequence(year, socket.assigns.date)
      end

    conduct_by_enrollment =
      Map.new(register.students, fn student ->
        totals =
          if sequence do
            Attendance.student_conduct(student.enrollment_id, {:sequence, sequence})
          else
            %{justified_hours: Decimal.new(0), unjustified_hours: Decimal.new(0), retards: 0}
          end

        {student.enrollment_id, totals}
      end)

    assign(socket,
      periods: register.periods,
      students: register.students,
      conduct_by_enrollment: conduct_by_enrollment
    )
  end

  def handle_params(params, _uri, socket) do
    date = parse_date(params["date"])

    {:noreply, socket |> assign(date: date) |> load_register()}
  end

  def handle_event("pick_date", %{"date" => date_str}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/school/classes/#{socket.assigns.cg.id}/register?date=#{date_str}")}
  end

  def handle_event("justify", %{"enrollment_id" => enrollment_id} = params, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.conduct_manager?(scope),
         %{} = student <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)) do
      note = presence(params["note"])

      case Attendance.justify_day(student.enrollment_id, socket.assigns.date, note) do
        {:ok, _count} -> {:noreply, load_register(socket)}
        {:error, _reason} -> {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unjustify", %{"enrollment_id" => enrollment_id}, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.conduct_manager?(scope),
         %{} = student <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)) do
      case Attendance.unjustify_day(student.enrollment_id, socket.assigns.date) do
        {:ok, _count} -> {:noreply, load_register(socket)}
        {:error, _reason} -> {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v

  defp status_label(nil), do: gettext("—")
  defp status_label(:present), do: gettext("P")
  defp status_label(:absent), do: gettext("A")
  defp status_label(:late), do: gettext("R")

  # Absence hours come from non-60-minute periods (e.g. 55 min → 0.9166…), so
  # round to 2 decimals and drop trailing zeros for a clean register: 0.92, 1, 0.
  defp fmt_hours(%Decimal{} = d) do
    s = d |> Decimal.round(2) |> Decimal.to_string(:normal)

    if String.contains?(s, ".") do
      s |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      s
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-register" class="space-y-6">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Cahier d'appel")}"}
        />

        <form id="register-date-form" phx-submit="pick_date" class="flex items-end gap-2">
          <label class="form-control">
            <span class="ta-eyebrow block mb-1">{gettext("Date")}</span>
            <input
              type="date"
              name="date"
              value={Date.to_iso8601(@date)}
              class="input input-bordered input-sm"
            />
          </label>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Afficher")}</button>
        </form>

        <p class="text-sm text-base-content/70">{Date.to_string(@date)}</p>

        <div class="overflow-x-auto">
          <table id="register-grid" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th :for={period <- @periods}>{period.label}</th>
                <th>{gettext("Justifiées")}</th>
                <th>{gettext("Injustifiées")}</th>
                <th>{gettext("Retards")}</th>
                <th :if={@can_edit?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={student <- @students} id={"register-row-#{student.enrollment_id}"}>
                <td>{student.student_name}</td>
                <td :for={period <- @periods} id={"cell-#{student.enrollment_id}-#{period.id}"}>
                  {status_label(Map.get(student.cells, period.id))}
                </td>
                <% conduct = Map.get(@conduct_by_enrollment, student.enrollment_id) %>
                <td>{fmt_hours(conduct.justified_hours)}</td>
                <td>{fmt_hours(conduct.unjustified_hours)}</td>
                <td>{conduct.retards}</td>
                <td :if={@can_edit?}>
                  <form
                    id={"justify-form-#{student.enrollment_id}"}
                    phx-submit="justify"
                    class="flex items-center gap-2"
                  >
                    <input type="hidden" name="enrollment_id" value={student.enrollment_id} />
                    <input
                      type="text"
                      name="note"
                      placeholder={gettext("Motif (optionnel)")}
                      class="input input-bordered input-xs"
                    />
                    <button
                      id={"justify-#{student.enrollment_id}"}
                      type="submit"
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Justifier")}
                    </button>
                    <button
                      id={"unjustify-#{student.enrollment_id}"}
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="unjustify"
                      phx-value-enrollment_id={student.enrollment_id}
                    >
                      {gettext("Annuler")}
                    </button>
                  </form>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.empty_state
          :if={@students == []}
          icon="hero-user-group"
          title={gettext("Aucun élève inscrit")}
        />
      </section>
    </Layouts.app>
    """
  end
end
