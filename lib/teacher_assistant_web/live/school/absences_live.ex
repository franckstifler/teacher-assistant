defmodule TeacherAssistantWeb.School.AbsencesLive do
  @moduledoc """
  Surveillant général → Absences (spec G, V02/V04; Vie scolaire redesign §2.2):
  one row per student-day of the current séquence with an absence, filtered by
  justification, class and period (all in the URL), the « Absences répétées »
  banner, and an inline « Justifier » with an optional precision.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.School.SchoolLifeComponents

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{EntryProgress, JustificationReason, Reference}
  alias TeacherAssistantWeb.{Authz, Dates}

  @filters ~w(unjustified justified all)
  @periods ~w(sequence week today)
  @page_size 50

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Discipline.can_manage_conduct?(scope) do
      {:ok, socket |> assign(open: nil, note: "") |> load()}
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
      lesson_count: scope |> Attendance.list_periods() |> Enum.count(&(&1.kind == :lesson)),
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
    note = socket.assigns.note |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

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

  defp visible(rows, assigns) do
    rows
    |> Enum.filter(&by_filter(&1, assigns.filter))
    |> Enum.filter(&(is_nil(assigns.class_id) or &1.class_group.id == assigns.class_id))
    |> Enum.filter(&in_period?(&1.date, assigns.period, assigns.today))
  end

  defp by_filter(row, "unjustified"), do: not row.justified?
  defp by_filter(row, "justified"), do: row.justified?
  defp by_filter(_row, "all"), do: true

  defp in_period?(_date, "sequence", _today), do: true
  defp in_period?(date, "today", today), do: date == today

  defp in_period?(date, "week", today),
    do: Date.compare(date, Date.beginning_of_week(today)) != :lt

  defp filter_label("unjustified"), do: gettext("À justifier")
  defp filter_label("justified"), do: gettext("Justifiées")
  defp filter_label("all"), do: gettext("Toutes")

  defp period_label("sequence", nil), do: gettext("Séquence en cours")
  defp period_label("sequence", seq), do: gettext("Séquence %{n}", n: seq.number)
  defp period_label("week", _seq), do: gettext("Cette semaine")
  defp period_label("today", _seq), do: gettext("Aujourd'hui")

  # One entry per student over the threshold: their séquence hours.
  defp repeated(rows) do
    rows
    |> Enum.filter(& &1.flagged?)
    |> Enum.uniq_by(& &1.enrollment.id)
    |> Enum.sort_by(
      &{-Decimal.to_float(&1.unjustified_hours), String.downcase(&1.student.full_name)}
    )
  end

  def render(assigns) do
    shown = visible(assigns.rows, assigns)
    page = if assigns.all?, do: shown, else: Enum.take(shown, @page_size)

    assigns =
      assign(assigns,
        filters: @filters,
        periods: @periods,
        shown: shown,
        page: page,
        repeated: repeated(assigns.rows),
        to_justify: Enum.count(assigns.rows, &(not &1.justified?))
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="absences" class="flex flex-col gap-4">
        <.page_header
          eyebrow={
            if @sequence,
              do: gettext("Vie scolaire · Séquence %{n}", n: @sequence.number),
              else: gettext("Vie scolaire")
          }
          title={gettext("Absences")}
          subtitle={
            ngettext(
              "%{count} absence à justifier",
              "%{count} absences à justifier",
              @to_justify
            ) <>
              " · " <>
              ngettext(
                "%{count} élève au-delà du seuil de %{hours} h",
                "%{count} élèves au-delà du seuil de %{hours} h",
                length(@repeated),
                hours: @alert_hours
              )
          }
        />

        <div
          :if={@repeated != []}
          id="repeated-banner"
          class="rounded-box border border-error/50 bg-error/10 px-3.5 py-3 text-[0.86rem]"
        >
          <b class="text-error">{gettext("Absences répétées.")}</b>
          <span :for={{row, i} <- Enum.with_index(@repeated)}>{if i > 0, do: ", "}<.link
            id={"repeated-#{row.enrollment.id}"}
            navigate={~p"/school/students/#{row.student.id}"}
            class="font-semibold hover:underline"
          >{row.student.full_name}</.link>
          <span class="whitespace-nowrap">({row.class_group.label} · {hours_label(
            row.unjustified_hours
          )})</span></span>
        </div>

        <form id="absence-filters" phx-change="filters" class="flex flex-wrap items-center gap-2.5">
          <div class="flex gap-0.5 rounded-[0.55rem] border border-base-300 bg-base-200 p-[3px]">
            <.link
              :for={f <- @filters}
              id={"filter-#{f}"}
              patch={absences_path(assigns, %{"filter" => f})}
              aria-current={@filter == f && "page"}
              class={[
                "rounded-[0.45rem] px-3 py-2 text-[0.8rem] font-semibold transition-colors",
                if(@filter == f,
                  do: "bg-primary text-primary-content",
                  else: "text-base-content/85 hover:text-base-content"
                )
              ]}
            >
              {filter_label(f)}
            </.link>
          </div>
          <select id="absence-class" name="class" class="select select-bordered select-sm w-auto">
            <option value="">{gettext("Toutes les classes")}</option>
            <option :for={c <- @classes} value={c.id} selected={c.id == @class_id}>{c.label}</option>
          </select>
          <select id="absence-period" name="period" class="select select-bordered select-sm w-auto">
            <option :for={p <- @periods} value={p} selected={p == @period}>
              {period_label(p, @sequence)}
            </option>
          </select>
        </form>

        <div class="overflow-hidden rounded-box border border-base-300 bg-base-100">
          <p :if={@shown == []} id="no-absences" class="px-4 py-5 text-sm text-base-content/75">
            {gettext("Aucune absence pour ce filtre.")}
          </p>
          <div :for={row <- @page} id={"row-#{row.id}"} class="ta-row-rule flex flex-col">
            <div class="flex items-center gap-3 px-4 py-2.5">
              <div class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="flex flex-wrap items-center gap-1.5 font-semibold">
                  {row.student.full_name}
                  <span class="font-normal text-base-content/75">· {row.class_group.label}</span>
                  <.overdue_badge row={row} />
                </span>
                <span class="text-[0.8rem] text-base-content/80">
                  {when_text(row, @today, @lesson_count)}
                </span>
                <span class="text-[0.8rem] text-base-content/80">
                  <%= if row.guardian do %>
                    {row.guardian.full_name} ·
                    <a href={"tel:#{row.guardian.phone_key}"} class="ta-num hover:underline">
                      {row.guardian.phone}
                    </a>
                  <% else %>
                    <span class="text-base-content/70">{gettext("Aucun contact")}</span>
                  <% end %>
                </span>
              </div>
              <div class="flex shrink-0 flex-col items-end gap-1.5">
                <span class={[
                  "ta-num text-[0.9rem] font-semibold",
                  if(row.minutes >= 180, do: "text-error", else: "text-warning")
                ]}>
                  {minutes_label(row.minutes)}
                </span>
                <button
                  :if={not row.justified?}
                  id={"open-#{row.id}"}
                  type="button"
                  class="btn btn-outline btn-sm"
                  phx-click="open"
                  phx-value-row={row.id}
                  aria-expanded={to_string(@open == row.id)}
                >
                  {gettext("Justifier")}
                </button>
                <.absence_status :if={row.justified?} row={row} />
              </div>
            </div>
            <div
              :if={@open == row.id and not row.justified?}
              id={"justify-panel-#{row.id}"}
              class="flex flex-wrap items-center gap-2 px-4 pb-3"
            >
              <.reason_chips row={row} />
              <form id={"note-#{row.id}"} phx-change="note" phx-submit="note" class="contents">
                <input
                  type="text"
                  name="note"
                  value={@note}
                  maxlength="200"
                  placeholder={gettext("Précision (facultatif)")}
                  aria-label={gettext("Précision (facultatif)")}
                  class="input input-bordered input-sm min-w-[200px] flex-1 sm:flex-none"
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

  # « lun. 6 oct. · 07:30 – 10:15 », or « … · journée » when every lesson was missed.
  defp when_text(row, today, lesson_count) do
    span =
      if length(row.periods) >= lesson_count and lesson_count > 0,
        do: gettext("journée"),
        else: "#{hm(hd(row.periods).start_time)} – #{hm(List.last(row.periods).end_time)}"

    "#{Dates.relative(row.date, today)} · #{span}"
  end

  defp minutes_label(minutes) do
    case {div(minutes, 60), rem(minutes, 60)} do
      {0, m} -> "#{m} min"
      {h, 0} -> "#{h} h"
      {h, m} -> "#{h} h #{String.pad_leading(to_string(m), 2, "0")}"
    end
  end

  defp hours_label(%Decimal{} = hours),
    do:
      "#{hours |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")} h"
end
