defmodule TeacherAssistantWeb.School.DisciplineLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Discipline
  alias TeacherAssistant.Organization
  alias TeacherAssistantWeb.SanctionLabels

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :discipline) do
      year = scope.current_academic_year
      sequences = if year, do: Organization.list_sequences(scope, year), else: []
      terms = if year, do: Organization.list_terms(scope, year), else: []
      roster = Enrollment.list_roster(scope, cg)

      {:ok,
       socket
       |> assign(
         cg: cg,
         year: year,
         sequences: sequences,
         terms: terms,
         can_edit?: Discipline.can_manage_conduct?(scope),
         roster: roster,
         issuers: Accounts.member_names(scope),
         sanction_types: Attendance.school_life_rules(scope).sanction_types_in_use,
         add_type: nil
       )
       |> ClassShell.assign_shell(count: length(roster))
       |> select_period(nil)}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, select_period(socket, params["period"])}

  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/school/classes/#{socket.assigns.cg.id}/discipline?period=#{param}"
     )}
  end

  # Which duration the add form asks for follows the chosen type.
  def handle_event("add_type", params, socket),
    do: {:noreply, assign(socket, add_type: params["type"])}

  def handle_event("add_sanction", params, socket) do
    scope = socket.assigns.current_scope

    with %{} = row <-
           Enum.find(socket.assigns.roster, &(&1.enrollment.id == params["enrollment_id"])),
         {:ok, type} <- fetch_type(socket.assigns.sanction_types, params["type"]),
         {:ok, date} <- Date.from_iso8601(params["date"] || "") do
      attrs = %{
        type: type,
        date: date,
        reason: presence(params["reason"]),
        duration_days: parse_duration(params["duration_days"]),
        duration_hours: parse_duration(params["duration_hours"])
      }

      case Discipline.add_sanction(scope, row.enrollment, attrs) do
        {:ok, _sanction} ->
          {:noreply,
           socket |> put_flash(:info, gettext("Sanction recorded.")) |> select_period(nil)}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, :duration_required} ->
          {:noreply,
           put_flash(socket, :error, gettext("Indiquez la durée de la consigne, en heures."))}

        {:error, :invalid_duration} ->
          {:noreply, put_flash(socket, :error, gettext("Une consigne dure de 1 à 40 heures."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not record the sanction."))}
      end
    else
      {:error, :invalid_type} ->
        {:noreply, put_flash(socket, :error, gettext("Ce type de sanction n'est pas utilisé."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("mark_parents_notified", %{"sanction_id" => sanction_id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = sanction <- Enum.find(socket.assigns.sanctions, &(&1.id == sanction_id)) do
      case Discipline.mark_parents_notified(scope, sanction) do
        {:ok, _} -> {:noreply, select_period(socket, nil)}
        {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
        {:error, _reason} -> {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_sanction", %{"sanction_id" => sanction_id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = sanction <- Enum.find(socket.assigns.sanctions, &(&1.id == sanction_id)) do
      case Discipline.delete_sanction(sanction, scope: scope) do
        :ok ->
          {:noreply,
           socket |> put_flash(:info, gettext("Sanction removed.")) |> select_period(nil)}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the sanction."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # Only the school's sanction types in use (spec KLM2).
  defp fetch_type(types, str) do
    case Enum.find(types, &(Atom.to_string(&1) == str)) do
      nil -> {:error, :invalid_type}
      type -> {:ok, type}
    end
  end

  # The type the add form shows: the one picked, else the select's first option.
  defp current_type(picked, types),
    do: Enum.find(types, &(Atom.to_string(&1) == picked)) || List.first(types)

  defp parse_duration(nil), do: nil
  defp parse_duration(""), do: nil

  defp parse_duration(str) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v

  defp select_period(socket, param) do
    year = socket.assigns.year

    period =
      (year && param && Organization.resolve_period(socket.assigns.current_scope, year, param)) ||
        socket.assigns[:period] ||
        default_period(socket.assigns.sequences)

    cg = socket.assigns.cg
    scope = socket.assigns.current_scope
    sanctions = if period, do: Discipline.list_sanctions(scope, cg, period), else: []

    discipline_by_enrollment =
      if period, do: Discipline.class_discipline(scope, cg, period), else: %{}

    assign(socket,
      period: period,
      period_param: period && Organization.period_param(period),
      sanctions: sanctions,
      discipline_by_enrollment: discipline_by_enrollment
    )
  end

  defp default_period([]), do: nil
  defp default_period([seq | _]), do: {:sequence, seq}

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp sequence_period?({:sequence, _}), do: true
  defp sequence_period?(_), do: false

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:discipline}>
        <:actions>
          <form :if={@sequences != []} id="discipline-period-form" phx-change="select_period">
            <.input
              type="select"
              id="discipline-period-select"
              name="period"
              value={@period_param}
              options={[
                {gettext("Séquences"),
                 for(s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", "seq:#{s.id}"})},
                {gettext("Trimestres"),
                 for(t <- @terms, do: {gettext("Trimestre") <> " #{t.position}", "trim:#{t.id}"})},
                {gettext("Année"), [{gettext("Année scolaire"), "annee"}]}
              ]}
            />
          </form>
        </:actions>

        <.empty_state
          :if={@period == nil}
          icon="hero-calendar-days"
          title={gettext("Aucune séquence")}
        />

        <div :if={@period} class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100">
          <table id="sanctions-log" class="table">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Type")}</th>
                <th>{gettext("Date")}</th>
                <th>{gettext("Durée")}</th>
                <th>{gettext("Motif")}</th>
                <th>{gettext("Émis par")}</th>
                <th>{gettext("Parents")}</th>
                <th :if={@can_edit?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={sanction <- @sanctions} id={"sanction-row-#{sanction.id}"}>
                <td>{sanction.enrollment.student.full_name}</td>
                <td>{SanctionLabels.type_label(sanction.type)}</td>
                <td>{Date.to_string(sanction.date)}</td>
                <td>{SanctionLabels.duration(sanction) || "—"}</td>
                <td>{sanction.reason || "—"}</td>
                <td>{@issuers[sanction.issued_by_user_id] || "—"}</td>
                <td id={"parents-#{sanction.id}"}>
                  <span :if={sanction.parents_notified_on} class="text-xs text-base-content/70">
                    {gettext("Parents notifiés le %{date}",
                      date: Date.to_string(sanction.parents_notified_on)
                    )}
                  </span>
                  <button
                    :if={is_nil(sanction.parents_notified_on) and @can_edit?}
                    id={"notify-parents-#{sanction.id}"}
                    type="button"
                    class="btn btn-ghost btn-sm"
                    phx-click="mark_parents_notified"
                    phx-value-sanction_id={sanction.id}
                  >
                    {gettext("Marquer les parents notifiés")}
                  </button>
                  <span
                    :if={is_nil(sanction.parents_notified_on) and not @can_edit?}
                    class="text-xs text-warning"
                  >
                    {gettext("Parents à notifier")}
                  </span>
                </td>
                <td :if={@can_edit?}>
                  <button
                    id={"delete-sanction-#{sanction.id}"}
                    type="button"
                    class="btn btn-ghost btn-sm btn-square text-error"
                    phx-click="delete_sanction"
                    phx-value-sanction_id={sanction.id}
                    data-confirm={gettext("Supprimer cette sanction ?")}
                    aria-label={gettext("Supprimer")}
                    title={gettext("Supprimer")}
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>

          <.empty_state
            :if={@sanctions == []}
            icon="hero-shield-check"
            title={gettext("Aucune sanction")}
          />
        </div>

        <div :if={@can_edit? and @period} class="ta-leaf space-y-3">
          <h2 class="text-sm font-semibold">{gettext("Ajouter une sanction")}</h2>
          <form
            id="discipline-add-form"
            phx-change="add_type"
            phx-submit="add_sanction"
            class="space-y-2"
          >
            <div class="grid gap-2 sm:grid-cols-6">
              <select
                name="enrollment_id"
                aria-label={gettext("Élève")}
                class="select select-bordered select-sm"
              >
                <option :for={row <- @roster} value={row.enrollment.id}>
                  {row.student.full_name}
                </option>
              </select>
              <select
                id="discipline-type-select"
                name="type"
                aria-label={gettext("Type de sanction")}
                class="select select-bordered select-sm"
              >
                <option :for={t <- @sanction_types} value={t}>{SanctionLabels.type_label(t)}</option>
              </select>
              <input
                type="date"
                name="date"
                aria-label={gettext("Date")}
                value={Date.to_iso8601(Date.utc_today())}
                class="input input-bordered input-sm"
              />
              <input
                :if={current_type(@add_type, @sanction_types) == :exclusion_temporaire}
                type="number"
                name="duration_days"
                min="1"
                placeholder={gettext("Durée (jours)")}
                aria-label={gettext("Durée (jours)")}
                class="input input-bordered input-sm"
              />
              <input
                :if={current_type(@add_type, @sanction_types) == :consigne}
                type="number"
                name="duration_hours"
                min="1"
                max="40"
                placeholder={gettext("Durée (heures)")}
                aria-label={gettext("Durée (heures)")}
                class="input input-bordered input-sm"
              />
              <input
                type="text"
                name="reason"
                placeholder={gettext("Motif (optionnel)")}
                aria-label={gettext("Motif (optionnel)")}
                class="input input-bordered input-sm"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </form>
        </div>

        <div :if={@period} class="overflow-x-auto">
          <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
            <h2 class="text-sm font-semibold">{gettext("Note de conduite")} /20</h2>
            <%!-- Conduct marks are entered in one place: the « Conduite » page. --%>
            <.link
              :if={@can_edit? and sequence_period?(@period)}
              id="conduct-link"
              navigate={~p"/school/conduct?class=#{@cg.id}&seq=#{elem(@period, 1).id}"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-pencil-square" class="size-4" />
              {gettext("Saisir sur la page Conduite")}
            </.link>
          </div>
          <table id="conduct-table" class="table">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Note de conduite")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @roster} id={"conduct-row-#{row.enrollment.id}"}>
                <td>{row.student.full_name}</td>
                <td>
                  <% summary = Map.get(@discipline_by_enrollment, row.enrollment.id) %>
                  <span class="ta-num">{summary && fmt(summary.note_de_conduite)}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.class_shell>
    </Layouts.app>
    """
  end
end
