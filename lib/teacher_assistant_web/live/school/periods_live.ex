defmodule TeacherAssistantWeb.School.PeriodsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{DayOfWeek, PeriodKind, SchoolCalendar}
  alias TeacherAssistant.{Accounts, Attendance}

  @blank_period %{"label" => "", "start_time" => "", "end_time" => "", "kind" => "lesson"}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope.current_workspace == nil ->
        {:ok, push_navigate(socket, to: ~p"/school")}

      not Attendance.can_manage_periods?(scope) ->
        {:ok, push_navigate(socket, to: ~p"/school")}

      true ->
        {:ok, profile} = Accounts.fetch_school_profile(scope)

        {:ok,
         socket
         |> assign(:scope, scope)
         |> assign(
           calendar: Attendance.school_calendar(scope),
           minutes: profile.default_lesson_minutes,
           new_period: @blank_period,
           days_error: nil,
           new_period_error: nil
         )
         |> load_periods()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="periods-page" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Horaires")} />

        <.form
          for={%{}}
          as={:days}
          id="days-form"
          phx-submit="save_days"
          class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <input type="hidden" name="days[lesson_days][]" value="" />
          <div class="flex flex-wrap gap-3">
            <label :for={day <- SchoolCalendar.all_days()} class="flex items-center gap-1.5 text-sm">
              <input
                type="checkbox"
                name="days[lesson_days][]"
                value={day}
                checked={day in @calendar.lesson_days}
                class="checkbox checkbox-sm"
              />
              {DayOfWeek.label(day)}
            </label>
          </div>
          <.input
            type="checkbox"
            name="days[wednesday_afternoon_off?]"
            value="true"
            checked={@calendar.wednesday_afternoon_off?}
            label={gettext("Mercredi après-midi libre (périodes à partir de 13 h)")}
          />
          <.input
            name="days[default_lesson_minutes]"
            value={@minutes}
            inputmode="numeric"
            label={gettext("Durée par défaut d'une heure de cours (min)")}
            class="input input-sm w-24 text-right"
          />
          <p :if={@days_error} id="days-error" class="text-sm text-error">{@days_error}</p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>

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

        <.form
          for={%{}}
          as={:new_period}
          id="new-period-form"
          phx-change="change_new_period"
          phx-submit="create_period"
          class="grid items-end gap-2 sm:grid-cols-5"
        >
          <.input name="new_period[label]" value={@new_period["label"]} label={gettext("Libellé")} />
          <.input
            name="new_period[start_time]"
            type="time"
            value={@new_period["start_time"]}
            label={gettext("Début")}
          />
          <.input
            name="new_period[end_time]"
            type="time"
            value={@new_period["end_time"]}
            label={gettext("Fin")}
          />
          <.input
            name="new_period[kind]"
            type="select"
            value={@new_period["kind"]}
            label={gettext("Type")}
            options={[{PeriodKind.label(:lesson), "lesson"}, {PeriodKind.label(:break), "break"}]}
          />
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter une période")}</button>
          <p :if={@new_period_error} id="new-period-error" class="text-sm text-error sm:col-span-5">
            {@new_period_error}
          </p>
        </.form>

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

  def handle_event("save_days", %{"days" => params}, socket) do
    scope = socket.assigns.scope

    case Attendance.update_school_days(scope, params) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(
           calendar: Attendance.school_calendar(scope),
           minutes: profile.default_lesson_minutes,
           days_error: nil
         )
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, {:slots_in_closed_cells, counts}} ->
        {:noreply, assign(socket, days_error: closed_message(counts))}

      {:error, :invalid_setting} ->
        {:noreply,
         assign(socket,
           days_error: gettext("Choisissez au moins un jour et une durée entre 1 et 240 minutes.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, assign(socket, days_error: gettext("Réglage non enregistré."))}
    end
  end

  def handle_event("change_new_period", %{"new_period" => params}, socket) do
    params = Map.merge(socket.assigns.new_period, params)

    params =
      with "" <- params["end_time"],
           {:ok, start} <- Time.from_iso8601(params["start_time"] <> ":00") do
        end_time = start |> Time.add(socket.assigns.minutes * 60) |> Calendar.strftime("%H:%M")
        Map.put(params, "end_time", end_time)
      else
        _ -> params
      end

    {:noreply, assign(socket, new_period: params)}
  end

  def handle_event("create_period", %{"new_period" => params}, socket) do
    scope = socket.assigns.scope
    position = (socket.assigns.periods |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)) + 1

    attrs =
      params
      |> normalize_period_params()
      |> Map.take(["label", "start_time", "end_time", "kind"])
      |> Map.put("position", position)

    case Attendance.create_period(scope, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(new_period: @blank_period, new_period_error: nil)
         |> load_periods()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        {:noreply,
         assign(socket,
           new_period_error:
             Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
         )}
    end
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
        params = normalize_period_params(params)

        case moved_slots(scope, period, params) do
          [] -> submit_period(socket, scope, period, params)
          counts -> {:noreply, put_flash(socket, :error, closed_message(counts))}
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

  defp submit_period(socket, scope, period, params) do
    form = AshPhoenix.Form.for_update(period, :update, as: "period", scope: scope)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, _period} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Période mise à jour."))
         |> load_periods()}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:noreply, Authz.put_not_allowed(socket)},
          else: {:noreply, put_flash(socket, :error, update_error(form))}
    end
  end

  # Spec J1: a new start time must not push the period's Wednesday lessons into the
  # closed afternoon.
  defp moved_slots(scope, period, %{"start_time" => start}) when is_binary(start) do
    case Time.from_iso8601(start) do
      {:ok, new_start} -> Attendance.slots_closed_by_period_move(scope, period, new_start)
      _ -> []
    end
  end

  defp moved_slots(_scope, _period, _params), do: []

  defp closed_message(counts) do
    detail =
      Enum.map_join(counts, ", ", fn {day, n} ->
        "#{n} #{String.downcase(DayOfWeek.label(day))}"
      end)

    gettext(
      "Des cours sont placés sur les créneaux fermés (%{detail}) : retirez-les de l'emploi du temps d'abord.",
      detail: detail
    )
  end

  # The validation's own message (overlap, end before start), else the generic one.
  defp update_error(form) do
    case AshPhoenix.Form.errors(form) do
      [] -> gettext("Impossible de mettre à jour la période.")
      errors -> Enum.map_join(errors, " ", fn {_field, message} -> message end)
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
