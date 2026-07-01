defmodule TeacherAssistantWeb.Teacher.DashboardLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    socket =
      if year do
        ws = scope.current_workspace
        plans = Academics.list_progression_plans(ws)
        kpis = Enum.map(plans, fn p -> %{plan: p, coverage: Academics.coverage_for_plan(p)} end)
        assign(socket, year: year, kpis: kpis)
      else
        assign(socket, year: nil, kpis: [])
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= if @year do %>
        <section id="teacher-dashboard" class="space-y-6">
          <.page_header eyebrow={gettext("Programme coverage")} title={gettext("Teacher dashboard")}>
            <:actions>
              <span class="ta-num rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs font-semibold text-base-content/70">
                {@year.name}
              </span>
            </:actions>
          </.page_header>

          <div class="flex flex-wrap gap-2">
            <.link navigate={~p"/teacher/import"} class="btn btn-outline btn-sm gap-2">
              <.icon name="hero-arrow-up-tray" class="size-4" />
              {gettext("Import a fiche")}
            </.link>
          </div>

          <div id="coverage-kpis" class="grid gap-3 sm:grid-cols-2">
            <div
              :for={kpi <- @kpis}
              id={"kpi-#{kpi.plan.id}"}
              class="ta-leaf flex flex-col gap-3"
            >
              <div class="flex items-baseline justify-between gap-3">
                <div class="font-display text-base font-semibold leading-snug">
                  {kpi.plan.title}
                </div>
                <span class="ta-eyebrow shrink-0">{gettext("covered")}</span>
              </div>
              <.coverage_ribbon rate={kpi.coverage.rate * 100} />
              <div class="flex flex-wrap items-center gap-2">
                <.link
                  navigate={~p"/teacher/plans/#{kpi.plan.id}"}
                  class="inline-flex w-fit items-center gap-1 text-sm font-semibold text-primary hover:underline"
                >
                  {gettext("Open plan")}
                  <.icon name="hero-arrow-right" class="size-3.5" />
                </.link>
                <.link
                  navigate={~p"/teacher/contexts/#{kpi.plan.teaching_context_id}/marks"}
                  class="btn btn-outline btn-xs gap-1"
                >
                  <.icon name="hero-pencil-square" class="size-3" />
                  {gettext("Marks")}
                </.link>
                <.link
                  navigate={~p"/teacher/contexts/#{kpi.plan.teaching_context_id}/marks/summary"}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Results")}
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
