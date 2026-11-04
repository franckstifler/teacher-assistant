defmodule TeacherAssistantWeb.School.AbsencesLive do
  @moduledoc """
  Surveillant général → Absences (spec G, V02/V04; Vie scolaire redesign §2.2; UX
  refonte batch 5): one row per student-day of the current séquence with an absence,
  under pills « À justifier » / « Au-delà du seuil » / « Justifiées » and class and
  period selects (all in the URL; the selects fold on phones). Each row: the
  student's unjustified hours for the séquence (red over the alert threshold), the
  day by lessons (« mar. 3 nov., cours 1 à 4 »), Maladie / Famille / Autre… (Autre…
  opens Convocation, Autre and a precision) and a call button to the guardian.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.School.SchoolLifeComponents

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{EntryProgress, JustificationReason, Reference}
  alias TeacherAssistantWeb.{Authz, Dates}

  @filters ~w(unjustified flagged justified)
  @periods ~w(sequence week today)
  @page_size 50

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Discipline.can_manage_conduct?(scope) do
      {:ok,
       socket
       |> assign(page_title: gettext("Absences"), open: nil, note: "")
       |> load()}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    class_ids = MapSet.new(socket.assigns.classes, & &1.id)

    {:noreply,
     assign(socket,
       filter: pick(params["filter"], @filters),
       period: pick(params["period"], @periods),
       class_id: if(MapSet.member?(class_ids, params["class"]), do: params["class"]),
       all?: params["all"] == "1"
     )}
  end

  defp pick(value, allowed), do: if(value in allowed, do: value, else: hd(allowed))

  # period id => its lesson number (« cours 4 » is the 4th lesson, breaks skipped)
  defp lesson_numbers(scope) do
    scope
    |> Attendance.list_periods()
    |> Enum.filter(&(&1.kind == :lesson))
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index(1)
    |> Map.new(fn {p, n} -> {p.id, n} end)
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    today = Reference.today()
    year = scope.current_academic_year

    rows =
      case Attendance.current_sequence_range(scope, today) do
        nil -> []
        {first, last} -> Attendance.absence_days(scope, first, last, today)
      end

    assign(socket,
      today: today,
      rows: rows,
      sequence:
        year && EntryProgress.default_sequence(Organization.list_sequences(scope, year), today),
      classes: if(year, do: Enrollment.list_class_groups(scope, year), else: []),
      lessons: lesson_numbers(scope),
      alert_hours: Attendance.school_life_rules(scope).absence_alert_hours
    )
  end

  def handle_event("filters", params, socket),
    do: {:noreply, push_patch(socket, to: absences_path(socket.assigns, params))}

  def handle_event("open", %{"row" => row_id}, socket),
    do:
      {:noreply,
       assign(socket, open: if(socket.assigns.open == row_id, do: nil, else: row_id), note: "")}

  def handle_event("note", %{"note" => note}, socket), do: {:noreply, assign(socket, note: note)}

  def handle_event("justify", %{"row" => row_id, "reason" => reason}, socket) do
    scope = socket.assigns.current_scope
    reason = Enum.find(JustificationReason.values(), &(Atom.to_string(&1) == reason))
    # the precision belongs to the row whose « Autre… » panel is open
    note =
      if socket.assigns.open == row_id,
        do: socket.assigns.note |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

    case Enum.find(socket.assigns.rows, &(&1.id == row_id)) do
      nil ->
        {:noreply, socket}

      row ->
        case Attendance.justify_day(scope, row.enrollment, row.date, reason, note) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               gettext("Absence de %{name} justifiée.", name: row.student.full_name)
             )
             |> assign(open: nil, note: "")
             |> load()}

          {:error, %Ash.Error.Forbidden{}} ->
            {:noreply, Authz.put_not_allowed(socket)}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # The URL for the filters in `params` (form fields), keeping the others.
  defp absences_path(assigns, params) do
    query =
      [
        filter: Map.get(params, "filter", assigns.filter),
        class: Map.get(params, "class", assigns.class_id),
        period: Map.get(params, "period", assigns.period),
        all: Map.get(params, "all")
      ]
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    ~p"/school/absences?#{query}"
  end

  defp by_filter(row, "unjustified"), do: not row.justified?
  defp by_filter(row, "flagged"), do: row.flagged? and not row.justified?
  defp by_filter(row, "justified"), do: row.justified?

  defp in_period?(_date, "sequence", _today), do: true
  defp in_period?(date, "today", today), do: date == today

  defp in_period?(date, "week", today),
    do: Date.compare(date, Date.beginning_of_week(today)) != :lt

  defp filter_label("unjustified"), do: gettext("À justifier")
  defp filter_label("flagged"), do: gettext("Au-delà du seuil")
  defp filter_label("justified"), do: gettext("Justifiées")

  # pill counts follow the class and period selects
  defp filter_count(_rows, "justified"), do: nil
  defp filter_count(rows, filter), do: Enum.count(rows, &by_filter(&1, filter))

  defp period_label("sequence", nil), do: gettext("Séquence en cours")
  defp period_label("sequence", seq), do: gettext("Séquence %{n}", n: seq.number)
  defp period_label("week", _seq), do: gettext("Cette semaine")
  defp period_label("today", _seq), do: gettext("Aujourd'hui")

  def render(assigns) do
    in_scope =
      Enum.filter(
        assigns.rows,
        &((is_nil(assigns.class_id) or &1.class_group.id == assigns.class_id) and
            in_period?(&1.date, assigns.period, assigns.today))
      )

    shown = Enum.filter(in_scope, &by_filter(&1, assigns.filter))
    page = if assigns.all?, do: shown, else: Enum.take(shown, @page_size)

    assigns =
      assign(assigns,
        filters: @filters,
        periods: @periods,
        in_scope: in_scope,
        shown: shown,
        page: page
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="absences" class="flex flex-col gap-4">
        <.page_header
          eyebrow={gettext("Vie scolaire")}
          title={gettext("Absences")}
          subtitle={
            [
              @sequence && gettext("Séquence %{n}", n: @sequence.number),
              ngettext(
                "seuil d'alerte %{count} h injustifiée",
                "seuil d'alerte %{count} h injustifiées",
                @alert_hours
              )
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" · ")
          }
        />

        <div class="flex flex-wrap items-center gap-2">
          <.filter_pills id="absence-pills" label={gettext("Absences")} class="min-w-0 flex-1">
            <:pill
              :for={f <- @filters}
              id={"filter-#{f}"}
              patch={absences_path(assigns, %{"filter" => f})}
              count={filter_count(@in_scope, f)}
              current={@filter == f}
            >
              {filter_label(f)}
            </:pill>
          </.filter_pills>
          <button
            type="button"
            class={[
              "btn btn-ghost btn-square sm:hidden",
              (@class_id || @period != "sequence") && "text-primary"
            ]}
            aria-label={gettext("Classe et période")}
            aria-controls="absence-filters"
            phx-click={JS.toggle_class("hidden", to: "#absence-filters")}
          >
            <.icon name="hero-funnel" class="size-5" />
          </button>
          <form
            id="absence-filters"
            phx-change="filters"
            class="hidden w-full flex-wrap items-center gap-2 sm:flex sm:w-auto"
          >
            <select
              id="absence-class"
              name="class"
              aria-label={gettext("Classe")}
              class="select select-bordered select-sm w-auto"
            >
              <option value="">{gettext("Toutes les classes")}</option>
              <option :for={c <- @classes} value={c.id} selected={c.id == @class_id}>
                {c.label}
              </option>
            </select>
            <select
              id="absence-period"
              name="period"
              aria-label={gettext("Période")}
              class="select select-bordered select-sm w-auto"
            >
              <option :for={p <- @periods} value={p} selected={p == @period}>
                {period_label(p, @sequence)}
              </option>
            </select>
          </form>
        </div>

        <div class="ta-section">
          <p :if={@shown == []} id="no-absences" class="px-4 py-5 text-sm text-base-content/75">
            {gettext("Aucune absence pour ce filtre.")}
          </p>
          <div
            :for={row <- @page}
            id={"row-#{row.id}"}
            class="ta-row-rule flex flex-col gap-2.5 px-4 py-3 last:border-b-0"
          >
            <div class="flex items-center gap-3">
              <div class="flex min-w-0 flex-1 flex-col">
                <span class="flex flex-wrap items-center gap-x-1.5 gap-y-0.5">
                  <.link
                    navigate={~p"/school/students/#{row.student.id}"}
                    class="font-semibold hover:underline"
                  >
                    {row.student.full_name}
                  </.link>
                  <.overdue_badge row={row} />
                </span>
                <span class="text-[0.8rem] text-base-content/75">
                  {row.class_group.label} · {when_text(row, @lessons)}
                </span>
              </div>
              <span
                :if={not row.justified?}
                id={"hours-#{row.id}"}
                class={[
                  "badge ta-num shrink-0 font-semibold",
                  if(row.flagged?,
                    do: "badge-error",
                    else: "border-warning/40 bg-warning/15 text-warning"
                  )
                ]}
                title={gettext("Heures injustifiées sur la séquence")}
              >
                {hours_label(row.unjustified_hours)}
              </span>
              <.absence_status :if={row.justified?} row={row} />
            </div>

            <div :if={not row.justified?} class="flex items-stretch gap-1.5">
              <.reason_chips row={row} reasons={[:maladie, :famille]} class="flex-1" />
              <button
                id={"open-#{row.id}"}
                type="button"
                class={[
                  "btn btn-sm flex-1 sm:flex-none",
                  if(@open == row.id, do: "btn-active", else: "btn-outline")
                ]}
                phx-click="open"
                phx-value-row={row.id}
                aria-expanded={to_string(@open == row.id)}
                aria-controls={"justify-panel-#{row.id}"}
              >
                {gettext("Autre…")}
              </button>
              <a
                :if={row.guardian}
                id={"call-#{row.id}"}
                href={"tel:#{row.guardian.phone_key}"}
                class="btn btn-outline btn-sm btn-square w-11 text-primary"
                aria-label={
                  gettext("Appeler %{name} : %{phone}",
                    name: row.guardian.full_name,
                    phone: row.guardian.phone
                  )
                }
                title={"#{row.guardian.full_name} · #{row.guardian.phone}"}
              >
                <.icon name="hero-phone" class="size-4" />
              </a>
              <.link
                :if={!row.guardian}
                navigate={~p"/school/students/#{row.student.id}"}
                class="btn btn-ghost btn-sm btn-square w-11 text-base-content/60"
                aria-label={gettext("Aucun contact")}
                title={gettext("Aucun contact")}
              >
                <.icon name="hero-phone-x-mark" class="size-4" />
              </.link>
            </div>

            <div
              :if={@open == row.id and not row.justified?}
              id={"justify-panel-#{row.id}"}
              class="flex flex-wrap items-center gap-2"
            >
              <.reason_chips row={row} reasons={[:convocation, :autre]} />
              <form id={"note-#{row.id}"} phx-change="note" phx-submit="note" class="contents">
                <input
                  type="text"
                  name="note"
                  value={@note}
                  maxlength="200"
                  placeholder={gettext("Précision (facultatif)")}
                  aria-label={gettext("Précision (facultatif)")}
                  class="input input-bordered input-sm min-w-[200px] flex-1"
                />
              </form>
            </div>
          </div>
          <div
            :if={@shown != []}
            id="absences-footer"
            class="flex items-center justify-between border-t border-base-300 px-4 py-2.5 text-[0.8rem] text-base-content/80"
          >
            <span>
              {gettext("%{shown} sur %{total} affichées", shown: length(@page), total: length(@shown))}
            </span>
            <.link
              :if={length(@page) < length(@shown)}
              id="show-all"
              patch={absences_path(assigns, %{"all" => "1"})}
              class="font-semibold text-info hover:underline"
            >
              {gettext("Afficher tout")}
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # « mar. 3 nov., cours 1 à 4 », « …, cours 4 », or « …, journée » when every
  # lesson was missed.
  defp when_text(row, lessons) do
    numbers = row.periods |> Enum.map(&lessons[&1.id]) |> Enum.reject(&is_nil/1) |> Enum.sort()
    "#{Dates.short(row.date)}, #{lesson_span(numbers, map_size(lessons))}"
  end

  defp lesson_span(numbers, all) when all > 0 and length(numbers) >= all, do: gettext("journée")
  defp lesson_span([], _all), do: gettext("journée")
  defp lesson_span([n], _all), do: gettext("cours %{n}", n: n)

  defp lesson_span([first | _] = numbers, _all) do
    last = List.last(numbers)

    if last - first + 1 == length(numbers),
      do: gettext("cours %{first} à %{last}", first: first, last: last),
      else: gettext("cours %{list}", list: Enum.join(numbers, ", "))
  end

  defp hours_label(%Decimal{} = hours),
    do:
      "#{hours |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")} h"
end
