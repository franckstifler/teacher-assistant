defmodule TeacherAssistantWeb.School.PeriodsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Permissions

  @kinds ~w(lesson break)

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope.current_workspace_type != :school ->
        {:ok, push_navigate(socket, to: ~p"/teacher")}

      not Permissions.admin?(scope) ->
        {:ok, push_navigate(socket, to: ~p"/school")}

      true ->
        {:ok,
         socket
         |> assign(:scope, scope)
         |> load_periods()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="periods-page" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Périodes")} />

        <div class="overflow-x-auto">
          <table :if={@periods != []} id="periods-table" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Position")}</th>
                <th>{gettext("Libellé")}</th>
                <th>{gettext("Début")}</th>
                <th>{gettext("Fin")}</th>
                <th>{gettext("Type")}</th>
                <th><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={period <- @periods} id={"period-row-#{period.id}"}>
                <td colspan="6">
                  <.form
                    for={to_form(period_form_params(period), as: :period)}
                    id={"period-form-#{period.id}"}
                    phx-submit="update_period"
                    class="grid items-end gap-2 sm:grid-cols-6"
                  >
                    <input type="hidden" name="period_id" value={period.id} />
                    <.input name="period[position]" value={period.position} label={gettext("Position")} />
                    <.input name="period[label]" value={period.label} label={gettext("Libellé")} />
                    <.input
                      name="period[start_time]"
                      type="time"
                      value={period.start_time}
                      label={gettext("Début")}
                    />
                    <.input
                      name="period[end_time]"
                      type="time"
                      value={period.end_time}
                      label={gettext("Fin")}
                    />
                    <.input
                      name="period[kind]"
                      type="select"
                      value={period.kind}
                      options={[{gettext("Cours"), "lesson"}, {gettext("Récréation"), "break"}]}
                      label={gettext("Type")}
                    />
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary btn-sm">
                        {gettext("Enregistrer")}
                      </button>
                      <button
                        type="button"
                        id={"period-delete-#{period.id}"}
                        class="btn btn-ghost btn-sm"
                        phx-click="delete_period"
                        phx-value-id={period.id}
                        data-confirm={gettext("Supprimer cette période ?")}
                      >
                        {gettext("Supprimer")}
                      </button>
                    </div>
                  </.form>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.empty_state
          :if={@periods == []}
          icon="hero-clock"
          title={gettext("No periods yet")}
        >
          <:action>
            <button id="seed-periods" type="button" class="btn btn-primary btn-sm" phx-click="seed">
              {gettext("Seed default schedule")}
            </button>
          </:action>
        </.empty_state>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("seed", _params, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) do
      :ok = Timetables.build_default_periods(scope.current_workspace)
      {:noreply, load_periods(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_period", %{"period_id" => id, "period" => params}, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) do
      case find_period(socket, id) do
        nil ->
          {:noreply, socket}

        period ->
          case Timetables.update_period(period, parse_period_attrs(params)) do
            {:ok, _period} ->
              {:noreply,
               socket
               |> put_flash(:info, gettext("Période mise à jour."))
               |> load_periods()}

            {:error, _error} ->
              {:noreply, put_flash(socket, :error, gettext("Impossible de mettre à jour la période."))}
          end
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_period", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    if Permissions.admin?(scope) do
      case find_period(socket, id) do
        nil ->
          {:noreply, socket}

        period ->
          case Timetables.delete_period(period) do
            :ok ->
              {:noreply, load_periods(socket)}

            {:error, :has_slots} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 gettext("This period has timetable entries and cannot be deleted.")
               )}
          end
      end
    else
      {:noreply, socket}
    end
  end

  defp find_period(socket, id) do
    Enum.find(socket.assigns.periods, &(&1.id == id))
  end

  defp load_periods(socket) do
    assign(socket, :periods, Timetables.list_periods(socket.assigns.scope.current_workspace))
  end

  defp period_form_params(period) do
    %{
      "position" => period.position,
      "label" => period.label,
      "start_time" => period.start_time,
      "end_time" => period.end_time,
      "kind" => to_string(period.kind)
    }
  end

  defp parse_period_attrs(params) do
    %{
      position: parse_integer(params["position"]),
      label: params["label"],
      start_time: parse_time(params["start_time"]),
      end_time: parse_time(params["end_time"]),
      kind: parse_kind(params["kind"])
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_time(nil), do: nil
  defp parse_time(""), do: nil
  defp parse_time(%Time{} = t), do: t

  defp parse_time(value) when is_binary(value) do
    normalized = if String.length(value) == 5, do: value <> ":00", else: value

    case Time.from_iso8601(normalized) do
      {:ok, time} -> time
      _ -> nil
    end
  end

  defp parse_kind(value) when value in @kinds, do: String.to_existing_atom(value)
  defp parse_kind(_), do: nil
end
