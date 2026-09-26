defmodule TeacherAssistantWeb.School.PeriodsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.PeriodKind
  alias TeacherAssistant.Attendance

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope.current_workspace == nil ->
        {:ok, push_navigate(socket, to: ~p"/school")}

      not Attendance.can_manage_periods?(scope) ->
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
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
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
                    for={
                      AshPhoenix.Form.for_update(period, :update,
                        as: "period",
                        scope: @current_scope
                      )
                      |> to_form()
                    }
                    id={"period-form-#{period.id}"}
                    phx-submit="update_period"
                    class="grid items-end gap-2 sm:grid-cols-6"
                  >
                    <input type="hidden" name="period_id" value={period.id} />
                    <.input
                      name="period[position]"
                      value={period.position}
                      label={gettext("Position")}
                    />
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
                      options={[
                        {PeriodKind.label(:lesson), "lesson"},
                        {PeriodKind.label(:break), "break"}
                      ]}
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
          title={gettext("Aucune période définie")}
        >
          <:action>
            <button id="seed-periods" type="button" class="btn btn-primary btn-sm" phx-click="seed">
              {gettext("Générer l'horaire par défaut")}
            </button>
          </:action>
        </.empty_state>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("seed", _params, socket) do
    scope = socket.assigns.scope

    case Attendance.build_default_periods(scope) do
      :ok -> {:noreply, load_periods(socket)}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, load_periods(socket)}
    end
  end

  def handle_event("update_period", %{"period_id" => id, "period" => params}, socket) do
    scope = socket.assigns.scope

    case find_period(socket, id) do
      nil ->
        {:noreply, socket}

      period ->
        form = AshPhoenix.Form.for_update(period, :update, as: "period", scope: scope)

        case AshPhoenix.Form.submit(form, params: normalize_period_params(params)) do
          {:ok, _period} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Période mise à jour."))
             |> load_periods()}

          {:error, form} ->
            if Authz.forbidden_form?(form),
              do: {:noreply, Authz.put_not_allowed(socket)},
              else:
                {:noreply,
                 put_flash(socket, :error, gettext("Impossible de mettre à jour la période."))}
        end
    end
  end

  def handle_event("delete_period", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = period <- find_period(socket, id),
         :ok <- Attendance.delete_period(scope, period) do
      {:noreply, load_periods(socket)}
    else
      nil ->
        {:noreply, socket}

      {:error, :has_slots} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Cette période a des cours à l'emploi du temps et ne peut pas être supprimée.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}
    end
  end

  defp find_period(socket, id) do
    Enum.find(socket.assigns.periods, &(&1.id == id))
  end

  defp load_periods(socket) do
    assign(socket, :periods, Attendance.list_periods(socket.assigns.scope))
  end

  # The HTML time input posts `HH:MM`; `Ash.Type.Time` needs full ISO
  # (`HH:MM:SS`), so widen the two time fields before the changeset casts them.
  # Position (string) and kind (enum) cast cleanly on their own.
  defp normalize_period_params(params) do
    params
    |> normalize_time_param("start_time")
    |> normalize_time_param("end_time")
  end

  defp normalize_time_param(params, key) do
    case params do
      %{^key => value} when is_binary(value) and byte_size(value) == 5 ->
        Map.put(params, key, value <> ":00")

      _ ->
        params
    end
  end
end
