defmodule TeacherAssistantWeb.School.PeriodsLive do
  @moduledoc """
  Paramètres → Horaires des cours (spec J1): the school week (lesson days, free
  Wednesday afternoon, length of a lesson) in one form with a save bar, then the
  day's periods as a list; a period is edited, added or deleted in a drawer.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.{DayOfWeek, PeriodKind, SchoolCalendar}
  alias TeacherAssistant.{Accounts, Attendance}

  import TeacherAssistantWeb.Drawer

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
         |> assign(:page_title, gettext("Horaires des cours"))
         |> assign(
           calendar: Attendance.school_calendar(scope),
           minutes: profile.default_lesson_minutes,
           editing: nil,
           new_period: @blank_period,
           days_error: nil,
           period_error: nil,
           new_period_error: nil
         )
         |> load_periods()}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="periods-page" class="mx-auto max-w-3xl space-y-6">
        <.back_header
          back={~p"/school/settings"}
          back_label={gettext("Paramètres")}
          title={gettext("Horaires des cours")}
        />

        <.form
          for={%{}}
          as={:days}
          id="days-form"
          phx-submit="save_days"
          phx-hook="DirtyForm"
        >
          <.settings_section id="week" title={gettext("Semaine")}>
            <div class="ta-setting !block space-y-3" role="group" aria-labelledby="lesson-days-label">
              <p id="lesson-days-label" class="text-[0.95rem] font-medium">
                {gettext("Jours de classe")}
              </p>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={day <- SchoolCalendar.all_days()}
                  id={"day-chip-#{day}"}
                  title={DayOfWeek.label(day)}
                  class={[
                    "grid h-11 min-w-11 cursor-pointer select-none place-items-center rounded-full border px-3 text-sm font-semibold transition-colors",
                    "border-base-300 text-base-content/75 hover:border-base-content/40",
                    "has-[:checked]:border-primary has-[:checked]:bg-primary/15 has-[:checked]:text-primary",
                    "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-primary"
                  ]}
                >
                  <input type="hidden" name={"days[lesson_days][#{day}]"} value="false" />
                  <input
                    type="checkbox"
                    name={"days[lesson_days][#{day}]"}
                    value="true"
                    checked={day in @calendar.lesson_days}
                    class="sr-only"
                  />
                  <span aria-hidden="true">{short_day(day)}</span>
                  <span class="sr-only">{DayOfWeek.label(day)}</span>
                </label>
              </div>
            </div>
            <.toggle_row
              name="days[wednesday_afternoon_off?]"
              checked={@calendar.wednesday_afternoon_off?}
              label={gettext("Mercredi après-midi libre")}
              help={gettext("Aucun cours le mercredi à partir de 13 h.")}
            />
            <.settings_row label={gettext("Durée d'une heure de cours")} for="days-minutes">
              <.unit_input
                id="days-minutes"
                name="days[default_lesson_minutes]"
                value={@minutes}
                inputmode="numeric"
                unit={gettext("min")}
              />
            </.settings_row>
            <%!-- `input-error` tells the DirtyForm hook the save failed: the bar stays. --%>
            <p
              :if={@days_error}
              id="days-error"
              role="alert"
              data-save-error
              class="border-t border-base-300/60 px-4 py-3 text-sm text-error sm:px-5"
            >
              {@days_error}
            </p>
          </.settings_section>
          <.save_bar />
        </.form>

        <.settings_section
          id="periods"
          title={gettext("La journée · %{count} cours", count: lesson_count(@periods))}
          subtitle={@periods != [] && gettext("Touchez un créneau pour le modifier.")}
        >
          <:actions>
            <button
              id="new-period-button"
              type="button"
              class="btn btn-outline min-h-11"
              phx-click="new_period"
            >
              <.icon name="hero-plus" class="size-4" />{gettext("Créneau")}
            </button>
          </:actions>
          <div :if={@periods != []} id="periods-list">
            <button
              :for={period <- @periods}
              type="button"
              id={"period-row-#{period.id}"}
              phx-click="edit_period"
              phx-value-id={period.id}
              class={[
                "ta-list-row w-full text-left",
                period.kind == :break && "bg-base-200/60 text-base-content/70",
                selected?(@editing, period) && "ta-list-row--selected"
              ]}
            >
              <span class="ta-num w-28 shrink-0 text-sm">
                {hm(period.start_time)}–{hm(period.end_time)}
              </span>
              <span class={[
                "min-w-0 flex-1 truncate text-[0.95rem]",
                period.kind == :lesson && "font-medium"
              ]}>
                {period.label}
              </span>
              <span :if={period.kind == :break} class="shrink-0 text-xs">
                {PeriodKind.label(:break)}
              </span>
              <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/45" />
            </button>
          </div>
          <div :if={@periods == []} class="px-4 pb-5 sm:px-5">
            <.empty_state icon="hero-clock" title={gettext("Aucune période définie")}>
              <:action>
                <button id="seed-periods" type="button" class="btn btn-primary" phx-click="seed">
                  {gettext("Générer l'horaire par défaut")}
                </button>
              </:action>
            </.empty_state>
          </div>
        </.settings_section>

        <.drawer
          :if={@editing == :new}
          id="period-drawer"
          eyebrow={gettext("Horaires")}
          title={gettext("Nouveau créneau")}
          on_close={JS.push("close_period")}
        >
          <.form
            for={%{}}
            as={:new_period}
            id="new-period-form"
            phx-change="change_new_period"
            phx-submit="create_period"
            class="space-y-1"
          >
            <.input
              name="new_period[label]"
              value={@new_period["label"]}
              label={gettext("Libellé")}
              placeholder={gettext("Cours 7, Récréation…")}
            />
            <div class="grid grid-cols-2 gap-3">
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
            </div>
            <.input
              name="new_period[kind]"
              type="select"
              value={@new_period["kind"]}
              label={gettext("Type")}
              options={kind_options()}
            />
            <p :if={@new_period_error} id="new-period-error" role="alert" class="text-sm text-error">
              {@new_period_error}
            </p>
          </.form>
          <:footer>
            <button type="button" class="btn btn-ghost" phx-click="close_period">
              {gettext("Annuler")}
            </button>
            <button type="submit" form="new-period-form" class="btn btn-primary">
              {gettext("Ajouter le créneau")}
            </button>
          </:footer>
        </.drawer>

        <.drawer
          :if={is_struct(@editing)}
          id="period-drawer"
          eyebrow={gettext("Créneau")}
          title={@editing.label}
          on_close={JS.push("close_period")}
        >
          <.form
            for={%{}}
            as={:period}
            id={"period-form-#{@editing.id}"}
            phx-submit="update_period"
            class="space-y-1"
          >
            <input type="hidden" name="period_id" value={@editing.id} />
            <.input name="period[label]" value={@editing.label} label={gettext("Libellé")} />
            <div class="grid grid-cols-2 gap-3">
              <.input
                name="period[start_time]"
                type="time"
                value={hm(@editing.start_time)}
                label={gettext("Début")}
              />
              <.input
                name="period[end_time]"
                type="time"
                value={hm(@editing.end_time)}
                label={gettext("Fin")}
              />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <.input
                name="period[kind]"
                type="select"
                value={@editing.kind}
                options={kind_options()}
                label={gettext("Type")}
              />
              <.input
                name="period[position]"
                type="number"
                min="1"
                inputmode="numeric"
                value={@editing.position}
                label={gettext("Position")}
                class="input w-full ta-num"
              />
            </div>
            <p :if={@period_error} id="period-error" role="alert" class="text-sm text-error">
              {@period_error}
            </p>
          </.form>
          <:footer>
            <button
              type="button"
              id={"period-delete-#{@editing.id}"}
              class="btn btn-ghost mr-auto text-error"
              phx-click="delete_period"
              phx-value-id={@editing.id}
              data-confirm={gettext("Supprimer cette période ?")}
            >
              {gettext("Supprimer")}
            </button>
            <button type="submit" form={"period-form-#{@editing.id}"} class="btn btn-primary">
              {gettext("Enregistrer")}
            </button>
          </:footer>
        </.drawer>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("save_days", %{"days" => params}, socket) do
    scope = socket.assigns.scope
    params = Map.update(params, "lesson_days", [], &lesson_days/1)

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

  def handle_event("new_period", _params, socket) do
    {:noreply, assign(socket, editing: :new, new_period: @blank_period, new_period_error: nil)}
  end

  def handle_event("edit_period", %{"id" => id}, socket) do
    case find_period(socket, id) do
      nil -> {:noreply, socket}
      period -> {:noreply, assign(socket, editing: period, period_error: nil)}
    end
  end

  def handle_event("close_period", _params, socket) do
    {:noreply, assign(socket, editing: nil, period_error: nil, new_period_error: nil)}
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
         |> assign(editing: nil, new_period: @blank_period, new_period_error: nil)
         |> put_flash(:info, gettext("Créneau ajouté."))
         |> load_periods()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        {:noreply,
         assign(socket,
           new_period: Map.merge(socket.assigns.new_period, params),
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
          counts -> {:noreply, assign(socket, period_error: closed_message(counts))}
        end
    end
  end

  def handle_event("delete_period", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = period <- find_period(socket, id),
         :ok <- Attendance.delete_period(scope, period) do
      {:noreply,
       socket
       |> assign(editing: nil, period_error: nil)
       |> put_flash(:info, gettext("Créneau supprimé."))
       |> load_periods()}
    else
      nil ->
        {:noreply, socket}

      {:error, :has_slots} ->
        {:noreply,
         assign(socket,
           period_error:
             gettext(
               "Cette période a des cours à l'emploi du temps et ne peut pas être supprimée."
             )
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
         |> assign(editing: nil, period_error: nil)
         |> put_flash(:info, gettext("Période mise à jour."))
         |> load_periods()}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:noreply, Authz.put_not_allowed(socket)},
          else: {:noreply, assign(socket, period_error: update_error(form))}
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

  # One field per day (`days[lesson_days][monday]` = "true" | "false") so the save
  # bar can tell each chip apart; the domain takes the list of checked days.
  defp lesson_days(%{} = by_day), do: for({day, "true"} <- by_day, do: day)
  defp lesson_days(days) when is_list(days), do: days
  defp lesson_days(_), do: []

  defp find_period(socket, id) do
    Enum.find(socket.assigns.periods, &(&1.id == id))
  end

  defp load_periods(socket) do
    assign(socket, :periods, Attendance.list_periods(socket.assigns.scope))
  end

  defp lesson_count(periods), do: Enum.count(periods, &(&1.kind == :lesson))

  defp selected?(%{id: id}, %{id: id}), do: true
  defp selected?(_editing, _period), do: false

  defp kind_options,
    do: [{PeriodKind.label(:lesson), "lesson"}, {PeriodKind.label(:break), "break"}]

  # « Lun », « Mar »… for the day chips (the full name is read out to screen readers).
  defp short_day(day), do: day |> DayOfWeek.label() |> String.slice(0, 3)

  defp hm(%Time{} = time), do: Calendar.strftime(time, "%H:%M")

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
