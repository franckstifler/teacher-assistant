defmodule TeacherAssistantWeb.School.AbsenceHoursLive do
  @moduledoc """
  Spec 2026-10-30 §4: « Heures d'absence » — where a class's bulletin absence hours come
  from, and, for a class typed by hand, one figure per student for a séquence or a
  trimester. Conduct managers change the source; they and the form master type.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  alias TeacherAssistant.Academics.{AbsenceHoursSource, EntryProgress, Reference}
  alias TeacherAssistant.{Attendance, Councils, Discipline, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.Scope
  alias TeacherAssistantWeb.{Authz, Numbers}

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :discipline) do
      year = scope.current_academic_year

      {:ok,
       socket
       |> assign(
         cg: cg,
         year: year,
         sequences: if(year, do: Organization.list_sequences(scope, year), else: []),
         terms: if(year, do: Organization.list_terms(scope, year), else: []),
         can_set?: Discipline.can_manage_conduct?(scope),
         appel?: Scope.module?(scope, :appel),
         errors: %{}
       )
       |> ClassShell.assign_shell(count: length(Enrollment.list_roster(scope, cg)))}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_params(params, _uri, socket),
    do: {:noreply, socket |> assign(errors: %{}) |> load(params["period"])}

  def handle_event("select_period", %{"period" => param}, socket),
    do: {:noreply, push_patch(socket, to: page_path(socket.assigns.cg, param))}

  def handle_event("set_source", %{"source" => value}, %{assigns: %{can_set?: true}} = socket) do
    with {:ok, source} <- AbsenceHoursSource.match(value),
         {:ok, cg} <-
           Enrollment.set_absence_hours_source(
             socket.assigns.current_scope,
             socket.assigns.cg,
             source
           ) do
      {:noreply,
       socket
       |> assign(cg: cg, errors: %{})
       |> clear_flash(:error)
       |> put_flash(:info, gettext("Réglage enregistré."))
       |> load(nil)}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  def handle_event("set_source", _params, socket), do: {:noreply, socket}

  def handle_event("save", %{"hours" => %{} = hours}, %{assigns: %{period: period}} = socket)
      when period != nil do
    scope = socket.assigns.current_scope

    case Attendance.save_typed_absences(scope, socket.assigns.cg, period, hours) do
      :ok ->
        {:ok, cg} = Enrollment.fetch_owned_class_group(scope, socket.assigns.cg.id)

        {:noreply,
         socket
         |> assign(cg: cg, errors: %{})
         |> clear_flash(:error)
         |> put_flash(:info, gettext("Heures d'absence enregistrées."))
         |> load(Organization.period_param(period))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, %{} = errors} when not is_struct(errors) ->
        {:noreply,
         socket
         |> assign(errors: errors, values: Map.merge(socket.assigns.values, hours))
         |> put_flash(:error, gettext("Rien n'a été enregistré : corrigez les heures en rouge."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Heures d'absence non enregistrées."))}
    end
  end

  def handle_event("save", _params, socket), do: {:noreply, socket}

  defp page_path(cg, nil), do: ~p"/school/classes/#{cg.id}/absence-hours"
  defp page_path(cg, param), do: ~p"/school/classes/#{cg.id}/absence-hours?period=#{param}"

  # The period follows the class's rhythm: séquences per séquence, trimesters per trimester.
  defp load(socket, param) do
    %{current_scope: scope, cg: cg, year: year} = socket.assigns
    source = Attendance.effective_absence_source(scope, cg)

    period =
      source != :roll_call && year && pick_period(socket.assigns, source, scope, year, param)

    rows = if period, do: Attendance.typed_absence_sheet(scope, cg, period), else: []

    assign(socket,
      source: source,
      period: period || nil,
      period_param: period && Organization.period_param(period),
      rows: rows,
      values: Map.new(rows, &{&1.enrollment.id, shown(&1.hours)}),
      published?: period && published?(scope, cg, period, socket.assigns.terms)
    )
  end

  defp pick_period(assigns, source, scope, year, param) do
    case {source, param && Organization.resolve_period(scope, year, param)} do
      {:typed_per_sequence, {:sequence, _} = period} -> period
      {:typed_per_term, {:trimester, _} = period} -> period
      {:typed_per_sequence, _} -> default_sequence(assigns.sequences)
      {:typed_per_term, _} -> default_term(assigns.terms)
    end
  end

  defp default_sequence(sequences) do
    case EntryProgress.default_sequence(sequences, Reference.today()) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  defp default_term(terms) do
    case Councils.default_term(terms, Reference.today()) do
      nil -> nil
      term -> {:trimester, term}
    end
  end

  # A séquence's figures print on its trimester's bulletin.
  defp published?(scope, cg, {:sequence, seq}, terms) do
    case Enum.find(terms, &(&1.id == seq.term_id)) do
      nil -> false
      term -> published?(scope, cg, {:trimester, term}, terms)
    end
  end

  defp published?(scope, cg, period, _terms),
    do: ReportCards.current_publication(scope, cg, period) != nil

  defp shown(nil), do: ""
  defp shown(%Decimal{} = hours), do: Numbers.decimal(hours, trim: true)

  defp source_options(appel?) do
    sources =
      if appel?,
        do: AbsenceHoursSource.values(),
        else: AbsenceHoursSource.values() -- [:roll_call]

    Enum.map(sources, &{AbsenceHoursSource.label(&1), &1})
  end

  defp period_options(:typed_per_sequence, sequences, _terms),
    do: for(s <- sequences, do: {gettext("Séquence") <> " #{s.number}", "seq:#{s.id}"})

  defp period_options(:typed_per_term, _sequences, terms),
    do: for(t <- terms, do: {gettext("Trimestre") <> " #{t.position}", "trim:#{t.id}"})

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:discipline}>
        <:actions>
          <form
            :if={@period}
            id="absence-hours-period-form"
            phx-change="select_period"
          >
            <.input
              type="select"
              id="absence-hours-period-select"
              name="period"
              value={@period_param}
              options={period_options(@source, @sequences, @terms)}
            />
          </form>
        </:actions>

        <section class="space-y-4">
          <div
            id="absence-source"
            class="rounded-[0.6rem] border border-base-300 bg-base-100 p-4 sm:p-5"
          >
            <h2 class="text-sm font-semibold">{gettext("Heures d'absence au bulletin")}</h2>
            <form
              :if={@can_set?}
              id="absence-source-form"
              phx-change="set_source"
              class="mt-2 max-w-sm"
            >
              <.input
                type="select"
                id="absence-source-select"
                name="source"
                value={@source}
                options={source_options(@appel?)}
              />
            </form>
            <p :if={!@can_set?} class="mt-1 text-sm text-base-content/70">
              {AbsenceHoursSource.label(@source)}
            </p>
            <p class="mt-2 text-xs text-base-content/60">
              {gettext(
                "Une seule source par classe : les heures saisies à la main ne s'ajoutent jamais à celles de l'appel."
              )}
            </p>
          </div>

          <p
            :if={@source == :roll_call}
            id="roll-call-note"
            class="text-sm text-base-content/70"
          >
            {gettext("Les heures du bulletin viennent de l'appel.")}
          </p>

          <.empty_state
            :if={@source != :roll_call and @period == nil}
            icon="hero-calendar-days"
            title={gettext("Aucune séquence")}
          />

          <div
            :if={@published?}
            id="published-warning"
            role="status"
            class="alert alert-warning text-sm"
          >
            <.icon name="hero-lock-closed" class="size-5" />
            <span>
              {gettext(
                "Bulletin publié : les heures imprimées ne changent qu'après retrait et nouvelle publication."
              )}
            </span>
          </div>

          <form
            :if={@period}
            id="typed-absences-form"
            phx-submit="save"
            class="rounded-[0.6rem] border border-base-300 bg-base-100"
          >
            <p class="border-b border-base-300 px-4 py-2 text-xs text-base-content/60">
              {gettext("Heures d'absence non justifiées, comptées sur les feuilles d'appel.")}
            </p>
            <ul class="divide-y divide-base-300">
              <li
                :for={{row, index} <- Enum.with_index(@rows, 1)}
                id={"absence-row-#{row.enrollment.id}"}
                class="flex items-center gap-3 px-4 py-2 transition-colors hover:bg-base-200/50"
              >
                <span class="w-6 text-right text-xs tabular-nums text-base-content/50">
                  {index}
                </span>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm">{row.student.full_name}</p>
                  <p class="flex flex-wrap gap-2 text-xs text-base-content/60">
                    <span :if={row.app_hours} id={"app-hours-#{row.enrollment.id}"}>
                      {gettext("dans l'app : %{hours}", hours: Numbers.hours(row.app_hours))}
                    </span>
                    <span
                      :if={row.prefilled? and !Map.has_key?(@errors, row.enrollment.id)}
                      id={"prefilled-#{row.enrollment.id}"}
                      class="badge badge-ghost badge-xs"
                    >
                      {gettext("pré-rempli")}
                    </span>
                    <span
                      :if={Map.has_key?(@errors, row.enrollment.id)}
                      id={"hours-error-#{row.enrollment.id}"}
                      class="text-error"
                    >
                      {gettext("Nombre d'heures invalide")}
                    </span>
                  </p>
                </div>
                <div class="w-24">
                  <.input
                    type="text"
                    inputmode="decimal"
                    id={"hours-#{row.enrollment.id}"}
                    name={"hours[#{row.enrollment.id}]"}
                    value={@values[row.enrollment.id]}
                    aria-label={gettext("Heures de %{name}", name: row.student.full_name)}
                    class={"input input-sm w-full text-right tabular-nums #{if Map.has_key?(@errors, row.enrollment.id), do: "input-error"}"}
                  />
                </div>
                <span class="text-xs text-base-content/50">h</span>
              </li>
            </ul>
            <div class="ta-stickyfoot sticky bottom-0 z-10 flex justify-end rounded-b-[0.6rem] border-t border-base-300 bg-base-100/95 px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur">
              <button
                type="submit"
                id="typed-absences-save"
                class="btn btn-primary btn-sm transition-transform active:scale-95"
                phx-disable-with={gettext("Enregistrement…")}
              >
                {gettext("Enregistrer")}
              </button>
            </div>
          </form>
        </section>
      </.class_shell>
    </Layouts.app>
    """
  end
end
