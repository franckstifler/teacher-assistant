defmodule TeacherAssistantWeb.Teacher.StatisticsLive do
  @moduledoc """
  « Mes statistiques » (spec audit follow-ups A4): every course of a teacher for a
  séquence, a trimester or the year, with the figures their pedagogical forms ask
  for — effectif, garçons, filles, notés, moyenne, réussite (overall and by sex),
  min, max and mentions. Trimester and year figures are the bulletin's
  (`Assessment.teacher_statistics/3`). The Proviseur and the Censeur open any
  teacher's page with `?teacher=<user id>`; anyone else sees their own.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment, Organization, ReportCards}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.TeacherCourses
  alias TeacherAssistantWeb.Authz

  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year
    {teacher, socket} = pick_teacher(socket, scope, params["teacher"])
    own? = teacher.id == scope.current_user.id

    {:ok,
     assign(socket,
       page_title: page_title(own?, teacher),
       year: year,
       teacher: teacher,
       own?: own?,
       periods: if(year, do: ReportCards.periods(scope, year), else: [])
     )}
  end

  defp pick_teacher(socket, scope, id) do
    case teacher_for(scope, id) do
      {:ok, user} -> {user, socket}
      :not_allowed -> {scope.current_user, Authz.put_not_allowed(socket)}
    end
  end

  @doc """
  Whose statistics a request shows: the signed-in member's without `teacher` (or with
  their own id); another member's for the Proviseur and the Censeur only
  (`ReportCards.can_publish?/1`). Shared with the print.
  """
  def teacher_for(scope, id) when id in [nil, ""], do: {:ok, scope.current_user}
  def teacher_for(%{current_user: %{id: id} = me}, id), do: {:ok, me}

  def teacher_for(scope, id) do
    with true <- ReportCards.can_publish?(scope),
         %{user: %User{} = user} <-
           Enum.find(Accounts.list_members(scope), &(&1.user_id == id)) do
      {:ok, user}
    else
      _ -> :not_allowed
    end
  end

  defp page_title(true, _teacher), do: gettext("Mes statistiques")

  defp page_title(false, teacher),
    do: gettext("Statistiques · %{name}", name: User.display_name(teacher))

  def handle_params(params, _uri, socket) do
    %{current_scope: scope, year: year, teacher: teacher} = socket.assigns

    period =
      (year && Organization.resolve_period(scope, year, params["period"])) || default(scope)

    rows = if period, do: Assessment.teacher_statistics(scope, teacher, period), else: []

    {:noreply, assign(socket, period: period, rows: rows)}
  end

  defp default(scope) do
    case TeacherCourses.current_sequence(scope) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  defp stats_path(assigns, overrides) do
    params =
      [
        period: assigns.period && Organization.period_param(assigns.period),
        teacher: !assigns.own? && assigns.teacher.id
      ]
      |> Keyword.merge(overrides)
      |> Enum.reject(fn {_k, v} -> v in [nil, false] end)

    ~p"/school/statistics/me?#{params}"
  end

  defp print_path(assigns) do
    params =
      [
        period: assigns.period && Organization.period_param(assigns.period),
        teacher: !assigns.own? && assigns.teacher.id
      ]
      |> Enum.reject(fn {_k, v} -> v in [nil, false] end)

    ~p"/school/statistics/me/print?#{params}"
  end

  defp current?(period, param),
    do: period != nil and Organization.period_param(period) == param

  defp source_line(_rows, nil), do: nil
  defp source_line(_rows, {:sequence, _}), do: nil

  defp source_line(rows, _period) do
    sources = for r <- rows, r.class_label == nil, do: r.source

    cond do
      sources == [] ->
        nil

      Enum.all?(sources, &(&1 == :published)) ->
        {:published, gettext("Chiffres des bulletins publiés")}

      Enum.all?(sources, &(&1 == :live)) ->
        {:live, gettext("Chiffres provisoires (bulletins non publiés)")}

      true ->
        {:mixed,
         gettext("Chiffres en partie provisoires (certains bulletins ne sont pas publiés)")}
    end
  end

  defp row_id(%{course: course, class_id: nil}), do: "stats-row-#{course.id}"
  defp row_id(%{course: course, class_id: class_id}), do: "stats-row-#{course.id}-#{class_id}"

  defp fmt(nil), do: "—"

  defp fmt(%Decimal{} = d),
    do: d |> Decimal.round(2) |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp short(nil), do: "—"

  defp short(%Decimal{} = d),
    do:
      d
      |> Decimal.round(1)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

  defp pct(nil), do: "—"
  defp pct(rate), do: "#{round(rate * 100)} %"

  defp mentions_text([]), do: "—"

  defp mentions_text(mentions),
    do: Enum.map_join(mentions, " · ", fn {label, n} -> "#{label} ×#{n}" end)

  def render(assigns) do
    assigns = assign(assigns, :source, source_line(assigns.rows, assigns.period))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="statistics" class="mx-auto max-w-5xl space-y-4">
        <.page_header
          eyebrow={gettext("Enseignement")}
          title={@page_title}
          subtitle={
            gettext("Effectifs, moyennes et taux de réussite de chaque cours, pour vos fiches.")
          }
        >
          <:actions :if={@rows != []}>
            <.link id="stats-print" href={print_path(assigns)} target="_blank" class="btn btn-sm">
              <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer")}
            </.link>
          </:actions>
        </.page_header>

        <nav
          :if={@periods != []}
          id="stats-periods"
          aria-label={gettext("Période")}
          class="ta-pills"
        >
          <.link
            :for={{param, label, _period} <- @periods}
            id={"stats-period-#{String.replace(param, ":", "-")}"}
            patch={stats_path(assigns, period: param)}
            aria-current={current?(@period, param) && "true"}
            class="ta-pill"
          >
            {label}
          </.link>
        </nav>

        <p
          :if={@source}
          id="stats-source"
          class={[
            "flex items-center gap-2 text-sm",
            if(elem(@source, 0) == :published, do: "text-success", else: "text-warning")
          ]}
        >
          <.icon
            name={if elem(@source, 0) == :published, do: "hero-check-badge", else: "hero-clock"}
            class="size-4"
          />
          {elem(@source, 1)}
        </p>

        <div :if={@rows == []} id="stats-empty">
          <.empty_state
            icon="hero-chart-bar"
            title={gettext("Aucun cours")}
            message={gettext("Les statistiques apparaissent dès qu'un cours vous est attribué.")}
          />
        </div>

        <div :if={@rows != []} class="overflow-x-auto rounded-box border border-base-300">
          <table id="stats-table" class="table table-sm ta-num">
            <thead>
              <tr>
                <th>{gettext("Cours")}</th>
                <th class="text-right">{gettext("Effectif")}</th>
                <th class="text-right" title={gettext("Garçons")}>{gettext("G")}</th>
                <th class="text-right" title={gettext("Filles")}>{gettext("F")}</th>
                <th class="text-right">{gettext("Notés")}</th>
                <th class="text-right">{gettext("Moyenne")}</th>
                <th class="text-right">{gettext("Réussite")}</th>
                <th class="text-right">{gettext("Réussite G")}</th>
                <th class="text-right">{gettext("Réussite F")}</th>
                <th class="text-right">{gettext("Min")}</th>
                <th class="text-right">{gettext("Max")}</th>
                <th class="max-sm:hidden">{gettext("Mentions")}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                id={row_id(row)}
                data-course={is_nil(row.class_label) && row.course.title}
                data-class={row.class_label}
                class={row.class_label && "text-base-content/80"}
              >
                <td class="min-w-40">
                  <span :if={is_nil(row.class_label)} class="font-medium">{row.course.title}</span>
                  <span :if={row.class_label} class="pl-4">↳ {row.class_label}</span>
                  <details
                    :if={row.mentions != []}
                    id={"stats-mentions-#{row_id(row)}"}
                    class="sm:hidden"
                  >
                    <summary class="cursor-pointer text-xs text-primary">
                      {gettext("Mentions")}
                    </summary>
                    <p class="text-xs">{mentions_text(row.mentions)}</p>
                  </details>
                </td>
                <td class="text-right" data-col="headcount">{row.headcount}</td>
                <td class="text-right" data-col="boys">{row.boys}</td>
                <td class="text-right" data-col="girls">{row.girls}</td>
                <td class="text-right" data-col="graded">{row.graded}</td>
                <td
                  class={[
                    "text-right font-semibold",
                    row.average && Decimal.lt?(row.average, 10) && "text-error"
                  ]}
                  data-col="average"
                >
                  {fmt(row.average)}
                </td>
                <td class="text-right" data-col="pass">{pct(row.pass_rate)}</td>
                <td class="text-right" data-col="pass-m">{pct(row.pass_m)}</td>
                <td class="text-right" data-col="pass-f">{pct(row.pass_f)}</td>
                <td class="text-right" data-col="min">{short(row.lowest)}</td>
                <td class="text-right" data-col="max">{short(row.highest)}</td>
                <td class="max-sm:hidden text-xs" data-col="mentions">
                  {mentions_text(row.mentions)}
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
