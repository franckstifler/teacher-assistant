defmodule TeacherAssistantWeb.School.CouncilsLive do
  @moduledoc """
  Conseils de classe (spec I3, mockup Censeur → "Conseils de classe"): one trimester at a
  time, one row per class with its council date, mark-entry rate and status (Saisie
  incomplète, Prêt, Tenu, Publié). A row opens the class's council. Proviseur and Censeur.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Councils, Enrollment, Organization, ReportCards}
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
         classes: Enrollment.list_class_groups(scope, year)
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    %{terms: terms, classes: classes, year: year, current_scope: scope} = socket.assigns

    {period, sequences} =
      case params do
        %{"period" => "annee"} ->
          {{:annual, year}, Organization.list_sequences(scope, year)}

        _ ->
          term =
            Enum.find(terms, &(&1.id == params["term"])) ||
              Councils.default_term(terms, Reference.today())

          {{:trimester, term}, term.sequences}
      end

    councils = Councils.for_period(scope, period)
    rates = EntryProgress.class_rates(scope, year, sequences)
    published = ReportCards.published_class_ids(scope, period)
    default_date = default_date(period, terms)

    rows =
      Enum.map(classes, fn cg ->
        council = Map.get(councils, cg.id)
        rate = Map.get(rates, cg.id)

        %{
          class_group: cg,
          date: (council && council.held_on) || default_date,
          rate: rate,
          status: status(MapSet.member?(published, cg.id), council, rate)
        }
      end)

    {:noreply,
     assign(socket,
       period: period,
       rows: rows,
       ready: Enum.count(rows, &(&1.status != :incomplete))
     )}
  end

  defp default_date({:trimester, term}, _terms), do: term.class_council_date
  defp default_date({:annual, _}, terms), do: List.last(terms).class_council_date

  defp period_params({:annual, _}), do: %{period: "annee"}
  defp period_params({:trimester, term}), do: %{term: term.id}

  defp period_title({:annual, _}), do: gettext("Censorat · Année")

  defp period_title({:trimester, term}),
    do: gettext("Censorat · Trimestre %{n}", n: term.position)

  defp status(true, _council, _rate), do: :published
  defp status(false, %{status: :held}, _rate), do: :held
  defp status(false, _council, 100), do: :ready
  defp status(false, _council, _rate), do: :incomplete

  defp status_label(:published), do: gettext("Publié")
  defp status_label(:held), do: gettext("Tenu")
  defp status_label(:ready), do: gettext("Prêt")
  defp status_label(:incomplete), do: gettext("Saisie incomplète")

  defp status_class(:incomplete), do: "badge-warning"
  defp status_class(_), do: "badge-success"

  defp date_text(nil), do: "—"
  defp date_text(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp rate_text(nil), do: "—"
  defp rate_text(rate), do: "#{rate} %"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="councils" class="space-y-4">
        <.page_header
          eyebrow={period_title(@period)}
          title={gettext("Conseils de classe")}
        >
          <:actions>
            <span id="councils-ready" class="ta-num text-sm text-base-content/70">
              {gettext("%{n} / %{total} classes prêtes", n: @ready, total: length(@rows))}
            </span>
          </:actions>
        </.page_header>

        <div role="tablist" class="tabs tabs-box w-fit">
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
                <th>{gettext("Date")}</th>
                <th class="text-right">{gettext("Saisie")}</th>
                <th>{gettext("Statut")}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                id={"council-row-#{row.class_group.id}"}
                class="transition-colors hover:bg-base-200/60"
              >
                <td class="font-semibold">
                  <.link
                    navigate={~p"/school/councils/#{row.class_group.id}?#{period_params(@period)}"}
                    class="link link-hover"
                  >
                    {row.class_group.label}
                  </.link>
                </td>
                <td class="ta-num">{date_text(row.date)}</td>
                <td class="ta-num text-right">{rate_text(row.rate)}</td>
                <td>
                  <span class={["badge badge-sm", status_class(row.status)]}>
                    {status_label(row.status)}
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
