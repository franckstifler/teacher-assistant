defmodule TeacherAssistantWeb.School.AbsenceTotalsLive do
  @moduledoc """
  Spec 2026-11-23 « Bilan des absences »: for a period (séquence, trimester, year) and
  one class or every class, each student's absence totals as the bulletin prints them,
  students at or over a typed threshold (default 20 h per séquence) marked. Every
  class shows only those students; one class shows all. Conduct managers only.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Discipline
  alias TeacherAssistant.Academics.AbsenceTotals
  alias TeacherAssistantWeb.Numbers
  alias TeacherAssistantWeb.School.AbsenceTotalsParams, as: Params

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      {:ok, assign(socket, page_title: gettext("Bilan des absences"), view: nil)}
    else
      {:ok,
       socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    view =
      with %{} = view <- socket.assigns.view,
           true <- Params.same_figures?(view, params) do
        # Only the threshold changed: filter what is already read.
        Params.refilter(view, params)
      else
        _ ->
          case Params.resolve(socket.assigns.current_scope, params) do
            {:ok, view} -> view
            :no_sequences -> nil
          end
      end

    {:noreply, assign(socket, view: view)}
  end

  def handle_event("pick", params, socket) do
    view = socket.assigns.view

    # The form always sends the threshold shown: the old period's default, unless it
    # was typed. A new period then starts from its own default.
    seuil =
      case AbsenceTotals.parse_threshold(params["seuil"], nil) do
        %Decimal{} = typed ->
          if Decimal.equal?(typed, view.default_threshold), do: nil, else: params["seuil"]

        nil ->
          nil
      end

    query = Params.query(view, period: params["period"], class: params["class"], seuil: seuil)
    {:noreply, push_patch(socket, to: ~p"/school/absence-totals?#{query}")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="absence-totals" class="flex flex-col gap-4">
        <.page_header
          eyebrow={gettext("Vie scolaire")}
          title={gettext("Bilan des absences")}
          subtitle={@view && Params.period_label(@view.period)}
        >
          <:actions :if={@view}>
            <a
              id="absence-print"
              href={~p"/school/absence-totals/print?#{Params.query(@view)}"}
              target="_blank"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer")}
            </a>
          </:actions>
        </.page_header>

        <div :if={@view == nil} id="absence-no-sequences">
          <.empty_state icon="hero-calendar-days" title={gettext("Aucune séquence")} />
        </div>

        <form
          :if={@view}
          id="absence-totals-form"
          phx-change="pick"
          class="grid gap-2 sm:grid-cols-[1fr_1fr_8rem]"
        >
          <.input
            type="select"
            id="absence-period-select"
            name="period"
            label={gettext("Période")}
            value={@view.period_param}
            options={Params.period_options(@view)}
          />
          <.input
            type="select"
            id="absence-class-select"
            name="class"
            label={gettext("Classe")}
            value={(@view.class_group && @view.class_group.id) || ""}
            options={[
              {gettext("Toutes les classes"), ""}
              | Enum.map(@view.class_groups, &{&1.label, &1.id})
            ]}
          />
          <.input
            type="text"
            id="absence-threshold"
            name="seuil"
            inputmode="decimal"
            label={gettext("Seuil (h)")}
            value={Numbers.decimal(@view.threshold, trim: true)}
            phx-debounce="400"
          />
        </form>

        <p :if={@view} id="absence-threshold-line" class="text-sm text-base-content/70">
          {Params.threshold_line(@view)} · {gettext("heures non justifiées")}
        </p>

        <div :if={@view && @view.groups == []} id="absence-empty">
          <.empty_state icon="hero-check-circle" title={gettext("Aucun élève au-dessus du seuil")} />
        </div>

        <.totals_group
          :for={group <- (@view && @view.groups) || []}
          group={group}
          threshold={@view.threshold}
        />
      </section>
    </Layouts.app>
    """
  end

  attr :group, :map, required: true
  attr :threshold, :any, required: true

  defp totals_group(assigns) do
    ~H"""
    <section id={"absence-class-#{@group.class_group.id}"} class="space-y-2">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h2 class="ta-eyebrow">{@group.class_group.label}</h2>
        <span id={"absence-source-#{@group.class_group.id}"} class="badge badge-ghost badge-sm">
          {source_label(@group.source)}
        </span>
      </div>
      <ul class="ta-section divide-y divide-base-300">
        <li
          :for={row <- @group.rows}
          id={"absence-row-#{row.enrollment.id}"}
          data-flagged={AbsenceTotals.flagged?(row, @threshold)}
          class="flex items-center gap-3 px-4 py-2 transition-colors hover:bg-base-200/50"
        >
          <%!-- the icon's room is kept on every row, so names line up --%>
          <span class="size-4 shrink-0">
            <.icon
              :if={AbsenceTotals.flagged?(row, @threshold)}
              name="hero-exclamation-triangle"
              class="size-4 text-warning"
            />
          </span>
          <%!-- phones: the figures go under the name, so long names keep the width --%>
          <div class="min-w-0 flex-1 sm:flex sm:items-center sm:gap-3">
            <p class="truncate text-sm sm:flex-1">{row.student.full_name}</p>
            <p class="flex flex-wrap gap-x-3 text-xs tabular-nums sm:shrink-0 sm:justify-end sm:text-sm">
              <span
                :if={@group.source == :typed and not row.recorded?}
                class="text-base-content/50"
              >
                {gettext("non saisi")}
              </span>
              <span
                :if={@group.source == :roll_call or row.recorded?}
                class={[
                  "font-semibold",
                  AbsenceTotals.flagged?(row, @threshold) && "text-warning"
                ]}
              >
                {Numbers.hours(row.unjustified_hours)} {gettext("NJ")}
              </span>
              <span :if={@group.source == :roll_call} class="text-base-content/70">
                {Numbers.hours(row.justified_hours)} {gettext("J")}
              </span>
              <span :if={@group.source == :roll_call} class="text-base-content/70">
                {ngettext("%{count} retard", "%{count} retards", row.retards)}
              </span>
            </p>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp source_label(:roll_call), do: gettext("Heures de l'appel")
  defp source_label(:typed), do: gettext("Heures saisies à la main")
end
