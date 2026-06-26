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
        <section id="teacher-dashboard" class="p-4 space-y-4">
          <h1 class="text-xl font-semibold">{gettext("Teacher dashboard")}</h1>
          <div id="coverage-kpis" class="grid gap-3">
            <div :for={kpi <- @kpis} id={"kpi-#{kpi.plan.id}"} class="card bg-base-100 shadow p-4">
              <div class="font-medium">{kpi.plan.title}</div>
              <div class="text-2xl font-bold">{round(kpi.coverage.rate * 100)}%</div>
              <div class="text-sm opacity-70">{gettext("covered")}</div>
              <.link navigate={~p"/teacher/plans/#{kpi.plan.id}"} class="link link-primary text-sm">{gettext("Open plan")}</.link>
            </div>
            <div :if={@kpis == []} class="opacity-70">
              {gettext("No progression plan yet.")}
              <.link navigate={~p"/teacher/setup"} class="link">{gettext("Set one up")}</.link>
            </div>
          </div>
        </section>
      <% else %>
        <section id="academic-year-setup-gate" class="p-4 space-y-3 text-center">
          <h1 class="text-xl font-semibold">{gettext("Welcome")}</h1>
          <p class="opacity-70">{gettext("Set up your academic year to get started.")}</p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary">{gettext("Start setup")}</.link>
        </section>
      <% end %>
    </Layouts.app>
    """
  end
end
