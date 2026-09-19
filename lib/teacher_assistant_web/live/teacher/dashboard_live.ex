defmodule TeacherAssistantWeb.Teacher.DashboardLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    socket =
      if year do
        ws = scope.current_workspace
        plans = Curriculum.unit_plans!(ws.id)

        kpis =
          Enum.map(plans, fn p ->
            %{plan: p, coverage: Curriculum.coverage_for_plan(p), context_id: link_context_id(p)}
          end)

        contexts_count = length(Curriculum.list_teaching_contexts(ws, year))
        current_seq = Organization.current_sequence(year, Date.utc_today())

        assign(socket,
          year: year,
          kpis: kpis,
          contexts_count: contexts_count,
          current_seq: current_seq,
          overall_rate: overall_rate(kpis),
          elapsed: elapsed_fraction(year)
        )
      else
        assign(socket, year: nil, kpis: [])
      end

    {:ok, socket}
  end

  # KPI action links (Marks/Roster/Results) navigate through a teaching
  # context. A solo plan already has one; a combined-course plan doesn't
  # (`teaching_context_id` is nil), so fall back to one of the course's
  # member contexts.
  defp link_context_id(%{teaching_context_id: id}) when not is_nil(id), do: id

  defp link_context_id(%{combined_course_id: course_id}) when not is_nil(course_id) do
    case Curriculum.get_course(course_id) do
      {:ok, course} ->
        case Curriculum.contexts_of_course!(course.id) do
          [%{id: id} | _] -> id
          [] -> nil
        end

      _ ->
        nil
    end
  end

  defp link_context_id(_), do: nil

  defp overall_rate([]), do: nil

  defp overall_rate(kpis) do
    planned = Enum.reduce(kpis, Decimal.new(0), &Decimal.add(&1.coverage.planned_hours, &2))
    covered = Enum.reduce(kpis, Decimal.new(0), &Decimal.add(&1.coverage.covered_hours, &2))

    if Decimal.equal?(planned, Decimal.new(0)),
      do: nil,
      else: Decimal.to_float(Decimal.div(covered, planned))
  end

  defp elapsed_fraction(year) do
    total = max(Date.diff(year.end_date, year.start_date), 1)
    (Date.diff(Date.utc_today(), year.start_date) / total) |> min(1.0) |> max(0.0)
  end

  # behind when coverage trails the elapsed school year by >10 points
  defp behind?(rate, elapsed), do: rate + 0.10 < elapsed

  # Render planned/covered Decimal hours compactly ("39" / "39.5"), for the
  # class-card subtitle. Additive display helper — no data is computed here.
  defp fmt_hours(%Decimal{} = d) do
    d = Decimal.round(d, 1)

    if Decimal.equal?(d, Decimal.round(d, 0)),
      do: d |> Decimal.round(0) |> Decimal.to_string(),
      else: Decimal.to_string(d)
  end

  defp fmt_hours(n), do: to_string(n)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= if @year do %>
        <section id="teacher-dashboard" class="flex flex-col gap-6">
          <.page_header eyebrow={gettext("My space")} title={gettext("Teacher dashboard")}>
            <:actions>
              <span class="ta-num inline-flex items-center rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold text-base-content/70">
                {@year.name}
              </span>
              <.link navigate={~p"/teacher/import"} class="btn btn-outline btn-sm gap-2">
                <.icon name="hero-arrow-up-tray" class="size-4" />
                {gettext("Import a fiche")}
              </.link>
            </:actions>
          </.page_header>

    <!-- KPI strip (mockup: the row of stat cards) -->
          <div id="dashboard-stats" class="grid grid-cols-3 gap-2 sm:gap-3">
            <.stat label={gettext("Classes")} value={"#{@contexts_count}"} />
            <.stat
              label={gettext("Overall coverage")}
              value={(@overall_rate && "#{round(@overall_rate * 100)}") || "—"}
              suffix={@overall_rate && "%"}
              tone={if @overall_rate && behind?(@overall_rate, @elapsed), do: :behind, else: :primary}
            />
            <.stat
              label={gettext("Séquence in progress")}
              value={(@current_seq && "S#{@current_seq.number}") || "—"}
            />
          </div>

    <!-- Coverage lag callout (mockup: "Retard de couverture") — only when the
             real overall rate trails the elapsed year -->
          <div
            :if={@overall_rate && behind?(@overall_rate, @elapsed)}
            id="coverage-lag"
            class="ta-leaf flex flex-col gap-1"
          >
            <p class="font-mono text-xs font-semibold uppercase tracking-[0.14em] text-warning">
              {gettext("Coverage lag")}
            </p>
            <p class="text-sm leading-relaxed text-base-content/70">
              {gettext(
                "About %{expected}% of the programme should be covered by now — your classes are at %{actual}% overall.",
                expected: round(@elapsed * 100),
                actual: round(@overall_rate * 100)
              )}
            </p>
          </div>

    <!-- "Mes classes" — one card per progression plan, from @kpis -->
          <div class="flex flex-col gap-3">
            <h2 class="text-lg font-semibold">{gettext("My classes")}</h2>

            <div id="coverage-kpis" class="grid gap-3 sm:grid-cols-2">
              <div
                :for={kpi <- @kpis}
                id={"kpi-#{kpi.plan.id}"}
                class="ta-leaf flex flex-col gap-3"
              >
                <div class="flex items-baseline justify-between gap-3">
                  <div class="min-w-0">
                    <div class="font-display text-base font-semibold leading-snug">
                      {kpi.plan.title}
                    </div>
                    <div class="ta-num mt-0.5 text-xs text-base-content/60">
                      {gettext("%{planned} h planned · %{covered} h covered",
                        planned: fmt_hours(kpi.coverage.planned_hours),
                        covered: fmt_hours(kpi.coverage.covered_hours)
                      )}
                    </div>
                  </div>
                  <span class={[
                    "badge badge-sm shrink-0",
                    (behind?(kpi.coverage.rate, @elapsed) && "badge-warning") || "badge-primary"
                  ]}>
                    {if behind?(kpi.coverage.rate, @elapsed),
                      do: gettext("behind"),
                      else: gettext("on track")}
                  </span>
                </div>

                <.coverage_ribbon
                  rate={kpi.coverage.rate * 100}
                  behind?={behind?(kpi.coverage.rate, @elapsed)}
                />

                <div class="flex flex-wrap items-center gap-2">
                  <.link
                    navigate={~p"/teacher/plans/#{kpi.plan.id}"}
                    class="inline-flex w-fit items-center gap-1 text-sm font-semibold text-primary hover:underline"
                  >
                    {gettext("Open plan")}
                    <.icon name="hero-arrow-right" class="size-3.5" />
                  </.link>
                  <.link
                    :if={kpi.context_id}
                    navigate={~p"/teacher/contexts/#{kpi.context_id}/marks"}
                    class="btn btn-outline btn-xs gap-1"
                  >
                    <.icon name="hero-pencil-square" class="size-3" />
                    {gettext("Marks")}
                  </.link>
                  <.link
                    :if={kpi.context_id}
                    navigate={~p"/teacher/contexts/#{kpi.context_id}/marks/summary"}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Results")}
                  </.link>
                  <.link
                    :if={kpi.context_id}
                    id={"kpi-roster-#{kpi.plan.id}"}
                    navigate={~p"/teacher/contexts/#{kpi.context_id}/roster"}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Roster")}
                  </.link>
                  <.link
                    id={"kpi-coverage-#{kpi.plan.id}"}
                    navigate={~p"/teacher/plans/#{kpi.plan.id}/coverage"}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Coverage")}
                  </.link>
                </div>
              </div>

              <div :if={@kpis == []} class="col-span-full">
                <.empty_state icon="hero-document-text" title={gettext("No progression plan yet.")}>
                  <:action>
                    <.link navigate={~p"/teacher/setup"} class="btn btn-primary btn-sm">
                      {gettext("Set one up")}
                    </.link>
                    <.link navigate={~p"/teacher/import"} class="btn btn-outline btn-sm">
                      {gettext("Import a fiche (PDF)")}
                    </.link>
                  </:action>
                </.empty_state>
              </div>
            </div>
          </div>
        </section>
      <% else %>
        <div id="academic-year-setup-gate">
          <.setup_gate
            icon="hero-academic-cap"
            eyebrow={gettext("Get started")}
            title={gettext("Welcome")}
            message={gettext("Set up your academic year to get started.")}
          >
            <:action>
              <.link navigate={~p"/teacher/setup"} class="btn btn-primary">
                {gettext("Start setup")}
              </.link>
            </:action>
          </.setup_gate>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
