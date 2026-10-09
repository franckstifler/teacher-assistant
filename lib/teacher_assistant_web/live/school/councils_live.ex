defmodule TeacherAssistantWeb.School.CouncilsLive do
  @moduledoc """
  Conseils de classe (spec I3, mockup Censeur → "Conseils de classe"): one trimester at a
  time, one row per class with its council date, mark-entry rate and status (À planifier,
  Planifié, Tenu, Clôturé). A row opens the class's council. Proviseur and Censeur.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Councils, Discipline, Enrollment, Organization, ReportCards}
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistant.Academics.{EntryProgress, Reference}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- ReportCards.can_publish?(scope),
         %{} = year <- scope.current_academic_year,
         [_ | _] = terms <- Organization.list_terms(scope, year) do
      {:ok,
       assign(socket,
         year: year,
         terms: terms,
         classes: Enrollment.list_class_groups(scope, year),
         planning: nil,
         plan_error: nil
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    %{terms: terms, year: year} = socket.assigns

    period =
      case params do
        %{"period" => "annee"} ->
          {:annual, year}

        _ ->
          {:trimester,
           Enum.find(terms, &(&1.id == params["term"])) ||
             Councils.default_term(terms, Reference.today())}
      end

    {:noreply, socket |> assign(period: period, planning: nil, plan_error: nil) |> load_rows()}
  end

  def handle_event("plan_open", %{"id" => id}, socket),
    do: {:noreply, assign(socket, planning: id, plan_error: nil)}

  def handle_event("plan_cancel", _params, socket),
    do: {:noreply, assign(socket, planning: nil, plan_error: nil)}

  def handle_event("plan", %{"plan" => %{"id" => id} = params}, socket) do
    scope = socket.assigns.current_scope
    cg = Enum.find(socket.assigns.classes, &(&1.id == id))

    with %{} <- cg,
         {:ok, date, time} <- parse_when(params) do
      case Councils.schedule(scope, cg, socket.assigns.period, date, time) do
        {:ok, _} ->
          {:noreply, socket |> assign(planning: nil, plan_error: nil) |> load_rows()}

        {:error, :locked} ->
          {:noreply,
           socket
           |> assign(planning: nil)
           |> put_flash(:error, gettext("Conseil verrouillé : bulletins publiés."))}

        {:error, _} ->
          {:noreply, assign(socket, plan_error: gettext("Date ou heure invalide."))}
      end
    else
      nil -> {:noreply, socket}
      :error -> {:noreply, assign(socket, plan_error: gettext("Date ou heure invalide."))}
    end
  end

  defp parse_when(params) do
    with {:ok, date} <- Date.from_iso8601(String.trim(params["date"] || "")),
         {:ok, time} <- parse_time(String.trim(params["time"] || "")) do
      {:ok, date, time}
    else
      _ -> :error
    end
  end

  # <input type="time"> submits "14:00" (no seconds).
  defp parse_time(<<_::binary-size(5)>> = hhmm), do: Time.from_iso8601(hhmm <> ":00")
  defp parse_time(other), do: Time.from_iso8601(other)

  defp load_rows(socket) do
    %{classes: classes, period: period, terms: terms, year: year, current_scope: scope} =
      socket.assigns

    sequences =
      case period do
        {:annual, _} -> Organization.list_sequences(scope, year)
        {:trimester, term} -> term.sequences
      end

    councils = Councils.for_period(scope, period)
    rates = EntryProgress.class_rates(scope, year, sequences)
    published = ReportCards.published_class_ids(scope, period)
    default_date = default_date(period, terms)

    rows =
      Enum.map(classes, fn cg ->
        council = Map.get(councils, cg.id)
        rate = Map.get(rates, cg.id)
        status = Councils.status(council, MapSet.member?(published, cg.id))

        %{
          class_group: cg,
          council: council,
          default_date: default_date,
          rate: rate,
          status: status,
          conduct_missing?: conduct_missing?(scope, cg, period)
        }
      end)

    assign(socket, rows: rows, counts: counts(rows))
  end

  defp conduct_missing?(scope, cg, period),
    do:
      scope
      |> Discipline.class_discipline(cg, period)
      |> Enum.any?(&(elem(&1, 1).note_de_conduite == nil))

  defp counts(rows) do
    by = Enum.frequencies_by(rows, & &1.status)

    %{
      total: length(rows),
      held: Map.get(by, :held, 0) + Map.get(by, :closed, 0),
      planned: Map.get(by, :planned, 0),
      to_plan: Map.get(by, :to_plan, 0)
    }
  end

  defp default_date({:trimester, term}, _terms), do: term.class_council_date
  defp default_date({:annual, _}, terms), do: List.last(terms).class_council_date

  defp period_params({:annual, _}), do: %{period: "annee"}
  defp period_params({:trimester, term}), do: %{term: term.id}

  defp period_title({:annual, _}), do: gettext("Année")
  defp period_title({:trimester, term}), do: gettext("Trimestre %{n}", n: term.position)

  defp status_label(:to_plan), do: gettext("À planifier")
  defp status_label(:planned), do: gettext("Planifié")
  defp status_label(:held), do: gettext("Tenu")
  defp status_label(:closed), do: gettext("Clôturé")

  defp status_class(:to_plan), do: "bg-warning/20 text-warning"
  defp status_class(:planned), do: "bg-info/20 text-info"
  defp status_class(_), do: "bg-primary/20 text-primary"

  defp date_text(%{status: :to_plan}), do: "—"
  defp date_text(%{council: nil}), do: "—"
  defp date_text(%{council: %{held_on: nil}}), do: "—"

  defp date_text(%{council: %{held_on: d, starts_at: nil}}), do: Dates.short(d)

  defp date_text(%{council: %{held_on: d, starts_at: t}}),
    do: Dates.short(d) <> " · " <> Calendar.strftime(t, "%H:%M")

  defp rate_text(nil), do: "—"
  defp rate_text(rate), do: "#{rate} %"

  attr :row, :map, required: true

  defp prep(assigns) do
    ~H"""
    <span :if={ready?(@row)} class="font-medium text-primary">{gettext("Prêt")}</span>
    <span :if={!ready?(@row)} class="ta-num text-base-content/70">
      {gettext("Notes %{rate}", rate: rate_text(@row.rate))}<span :if={@row.conduct_missing?}> · {gettext(
        "conduite à saisir"
      )}</span>
    </span>
    """
  end

  defp prefill_date(%{council: %{held_on: %Date{} = d}}), do: Date.to_iso8601(d)
  defp prefill_date(%{default_date: %Date{} = d}), do: Date.to_iso8601(d)
  defp prefill_date(_), do: ""

  defp prefill_time(%{council: %{starts_at: %Time{} = t}}), do: Calendar.strftime(t, "%H:%M")
  defp prefill_time(_), do: ""

  defp ready?(%{rate: 100, conduct_missing?: false}), do: true
  defp ready?(_), do: false

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="councils" class="space-y-4">
        <.page_header eyebrow={period_title(@period)} title={gettext("Conseils de classe")}>
          <:actions>
            <span id="councils-summary" class="ta-num text-sm text-base-content/70">
              {ngettext("%{n} classe", "%{n} classes", @counts.total, n: @counts.total)} · {ngettext(
                "%{n} tenu",
                "%{n} tenus",
                @counts.held,
                n: @counts.held
              )} · {ngettext(
                "%{n} planifié",
                "%{n} planifiés",
                @counts.planned,
                n: @counts.planned
              )} · {gettext("%{n} à planifier", n: @counts.to_plan)}
            </span>
          </:actions>
        </.page_header>

        <div role="tablist" class="tabs tabs-box w-fit max-w-full">
          <.link
            :for={t <- @terms}
            id={"term-#{t.id}"}
            role="tab"
            patch={~p"/school/councils?term=#{t.id}"}
            class={["tab", @period == {:trimester, t} && "tab-active"]}
          >
            {gettext("Trimestre %{n}", n: t.position)}
          </.link>
          <.link
            id="term-annee"
            role="tab"
            patch={~p"/school/councils?period=annee"}
            class={["tab", match?({:annual, _}, @period) && "tab-active"]}
          >
            {gettext("Année")}
          </.link>
        </div>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table id="councils-table" class="table">
            <thead>
              <tr>
                <th>{gettext("Classe")}</th>
                <th class="hidden md:table-cell">{gettext("Date")}</th>
                <th class="hidden md:table-cell">{gettext("Préparation")}</th>
                <th>{gettext("Statut")}</th>
                <th><span class="sr-only">{gettext("Action")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                id={"council-row-#{row.class_group.id}"}
                class="align-top transition-colors hover:bg-base-200/60"
              >
                <td class="font-semibold">
                  <.link
                    id={"class-link-#{row.class_group.id}"}
                    navigate={~p"/school/councils/#{row.class_group.id}?#{period_params(@period)}"}
                    class="link link-hover"
                  >
                    {row.class_group.label}
                  </.link>
                  <div class="mt-0.5 text-xs font-normal md:hidden">
                    <div class="ta-num mb-0.5">{date_text(row)}</div>
                    <.prep row={row} />
                  </div>
                </td>
                <td class="ta-num hidden whitespace-nowrap md:table-cell">{date_text(row)}</td>
                <td class="hidden text-sm md:table-cell">
                  <.prep row={row} />
                </td>
                <td>
                  <span
                    data-status={row.status}
                    class={[
                      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap",
                      status_class(row.status)
                    ]}
                  >
                    {status_label(row.status)}
                  </span>
                </td>
                <td class="md:min-w-44">
                  <button
                    :if={row.status == :to_plan && @planning != row.class_group.id}
                    id={"plan-#{row.class_group.id}"}
                    type="button"
                    phx-click="plan_open"
                    phx-value-id={row.class_group.id}
                    class="btn btn-primary btn-sm gap-1"
                  >
                    <.icon name="hero-calendar-days" class="size-4" /> {gettext("Planifier")}
                  </button>
                  <.form
                    :if={row.status == :to_plan && @planning == row.class_group.id}
                    for={%{}}
                    as={:plan}
                    id={"plan-form-#{row.class_group.id}"}
                    phx-submit="plan"
                    class="flex flex-wrap items-end gap-2"
                  >
                    <input type="hidden" name="plan[id]" value={row.class_group.id} />
                    <input
                      type="date"
                      name="plan[date]"
                      value={prefill_date(row)}
                      aria-label={gettext("Date")}
                      class="input input-sm w-full md:w-40"
                    />
                    <input
                      type="time"
                      name="plan[time]"
                      value={prefill_time(row)}
                      aria-label={gettext("Heure")}
                      class="input input-sm w-full md:w-28"
                    />
                    <button type="submit" class="btn btn-primary btn-sm">
                      {gettext("Enregistrer")}
                    </button>
                    <button type="button" phx-click="plan_cancel" class="btn btn-ghost btn-sm">
                      {gettext("Annuler")}
                    </button>
                    <p :if={@plan_error} data-plan-error class="w-full text-xs text-error">
                      {@plan_error}
                    </p>
                  </.form>
                  <.link
                    :if={row.status == :planned}
                    id={"prepare-#{row.class_group.id}"}
                    navigate={~p"/school/councils/#{row.class_group.id}?#{period_params(@period)}"}
                    class="btn btn-outline btn-sm gap-1"
                  >
                    <.icon name="hero-clipboard-document-list" class="size-4" /> {gettext("Préparer")}
                  </.link>
                  <a
                    :if={row.status in [:held, :closed]}
                    id={"pv-#{row.class_group.id}"}
                    href={~p"/school/councils/#{row.class_group.id}/print?#{period_params(@period)}"}
                    target="_blank"
                    class="btn btn-ghost btn-sm gap-1"
                  >
                    <.icon name="hero-document-text" class="size-4" /> {gettext("Voir le PV")}
                  </a>
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
