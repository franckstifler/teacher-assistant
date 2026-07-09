defmodule TeacherAssistantWeb.School.DisciplineLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistantWeb.SanctionLabels

  @sanction_types [
    :avertissement,
    :blame,
    :exclusion_temporaire,
    :exclusion_definitive,
    :consigne
  ]

  @type_strings Map.new(@sanction_types, &{Atom.to_string(&1), &1})

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- authorized?(scope, cg) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      terms = if year, do: Academics.list_terms(year), else: []

      {:ok,
       socket
       |> assign(
         cg: cg,
         year: year,
         sequences: sequences,
         terms: terms,
         can_edit?: Permissions.conduct_manager?(scope),
         roster: Academics.list_roster(cg),
         sanction_types: @sanction_types
       )
       |> select_period(nil)}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp authorized?(scope, cg) do
    Permissions.conduct_manager?(scope) or Permissions.admin_or_form_master?(scope, cg)
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, select_period(socket, params["period"])}

  def handle_event("select_period", %{"period" => param}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/school/classes/#{socket.assigns.cg.id}/discipline?period=#{param}"
     )}
  end

  def handle_event("add_sanction", params, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.conduct_manager?(scope),
         %{} = row <-
           Enum.find(socket.assigns.roster, &(&1.enrollment.id == params["enrollment_id"])),
         {:ok, type} <- fetch_type(params["type"]),
         {:ok, date} <- Date.from_iso8601(params["date"] || "") do
      duration_days =
        if type == :exclusion_temporaire, do: parse_duration(params["duration_days"])

      attrs = %{
        type: type,
        date: date,
        reason: presence(params["reason"]),
        duration_days: duration_days
      }

      case Discipline.add_sanction(row.enrollment, attrs, scope.current_user.id) do
        {:ok, _sanction} ->
          {:noreply,
           socket |> put_flash(:info, gettext("Sanction recorded.")) |> select_period(nil)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not record the sanction."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_sanction", %{"sanction_id" => sanction_id}, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.conduct_manager?(scope),
         %{} = sanction <- Enum.find(socket.assigns.sanctions, &(&1.id == sanction_id)) do
      case Discipline.delete_sanction(sanction) do
        :ok ->
          {:noreply, socket |> put_flash(:info, gettext("Sanction removed.")) |> select_period(nil)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not remove the sanction."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_note", %{"enrollment_id" => enrollment_id, "value" => value}, socket) do
    scope = socket.assigns.current_scope

    with true <- Permissions.conduct_manager?(scope),
         {:sequence, sequence} <- socket.assigns.period,
         %{} = row <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == enrollment_id)) do
      case Discipline.set_conduct_mark(row.enrollment, sequence, value, scope.current_user.id) do
        {:ok, _mark} ->
          {:noreply,
           socket |> put_flash(:info, gettext("Note de conduite enregistrée.")) |> select_period(nil)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Enter a value between 0 and 20."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  defp fetch_type(str) when is_binary(str) do
    case Map.fetch(@type_strings, str) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, :invalid_type}
    end
  end

  defp fetch_type(_), do: {:error, :invalid_type}

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
      (year && param && Academics.resolve_period(year, param)) ||
        socket.assigns[:period] ||
        default_period(socket.assigns.sequences)

    cg = socket.assigns.cg
    sanctions = if period, do: Discipline.list_sanctions(cg, period), else: []
    discipline_by_enrollment = if period, do: Discipline.class_discipline(cg, period), else: %{}

    assign(socket,
      period: period,
      period_param: period && Academics.period_param(period),
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-discipline" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={"#{@cg.label} — #{gettext("Discipline")}"}>
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
        </.page_header>

        <.empty_state
          :if={@period == nil}
          icon="hero-calendar-days"
          title={gettext("Aucune séquence")}
        />

        <div :if={@period} class="overflow-x-auto">
          <table id="sanctions-log" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Type")}</th>
                <th>{gettext("Date")}</th>
                <th>{gettext("Durée (jours)")}</th>
                <th>{gettext("Motif")}</th>
                <th>{gettext("Émis par")}</th>
                <th :if={@can_edit?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={sanction <- @sanctions} id={"sanction-row-#{sanction.id}"}>
                <td>{sanction.enrollment.student.full_name}</td>
                <td>{SanctionLabels.type_label(sanction.type)}</td>
                <td>{Date.to_string(sanction.date)}</td>
                <td>{if sanction.type == :exclusion_temporaire, do: sanction.duration_days, else: "—"}</td>
                <td>{sanction.reason || "—"}</td>
                <td>{sanction.issued_by_user_id || "—"}</td>
                <td :if={@can_edit?}>
                  <button
                    id={"delete-sanction-#{sanction.id}"}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="delete_sanction"
                    phx-value-sanction_id={sanction.id}
                    data-confirm={gettext("Supprimer cette sanction ?")}
                  >
                    {gettext("Supprimer")}
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
          <form id="discipline-add-form" phx-submit="add_sanction" class="space-y-2">
            <div class="grid gap-2 sm:grid-cols-5">
              <select name="enrollment_id" class="select select-bordered select-sm">
                <option :for={row <- @roster} value={row.enrollment.id}>
                  {row.student.full_name}
                </option>
              </select>
              <select id="discipline-type-select" name="type" class="select select-bordered select-sm">
                <option :for={t <- @sanction_types} value={t}>{SanctionLabels.type_label(t)}</option>
              </select>
              <input
                type="date"
                name="date"
                value={Date.to_iso8601(Date.utc_today())}
                class="input input-bordered input-sm"
              />
              <input
                type="number"
                name="duration_days"
                min="1"
                placeholder={gettext("Durée (jours)")}
                class="input input-bordered input-sm"
              />
              <input
                type="text"
                name="reason"
                placeholder={gettext("Motif (optionnel)")}
                class="input input-bordered input-sm"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
          </form>
        </div>

        <div :if={@period} class="overflow-x-auto">
          <h2 class="text-sm font-semibold mb-2">{gettext("Note de conduite")} /20</h2>
          <table id="conduct-table" class="table table-zebra">
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
                  <form
                    :if={@can_edit? and sequence_period?(@period)}
                    id={"note-form-#{row.enrollment.id}"}
                    phx-submit="set_note"
                    class="flex items-center gap-2"
                  >
                    <input type="hidden" name="enrollment_id" value={row.enrollment.id} />
                    <input
                      type="number"
                      name="value"
                      min="0"
                      max="20"
                      step="0.5"
                      value={summary && fmt(summary.note_de_conduite)}
                      class="input input-bordered input-xs w-20"
                    />
                    <button type="submit" class="btn btn-ghost btn-xs">{gettext("Enregistrer")}</button>
                  </form>
                  <span :if={!(@can_edit? and sequence_period?(@period))}>
                    {summary && fmt(summary.note_de_conduite)}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

end
