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
          <header class="flex flex-wrap items-end justify-between gap-3">
            <div>
              <p class="ta-eyebrow">{gettext("Programme coverage")}</p>
              <h1 class="mt-1 text-2xl font-bold sm:text-3xl">
                {gettext("Teacher dashboard")}
              </h1>
            </div>
            <span class="ta-num rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs font-semibold text-base-content/70">
              {@year.name}
            </span>
          </header>

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
              <.link
                navigate={~p"/teacher/plans/#{kpi.plan.id}"}
                class="inline-flex w-fit items-center gap-1 text-sm font-semibold text-primary hover:underline"
              >
                {gettext("Open plan")}
                <.icon name="hero-arrow-right" class="size-3.5" />
              </.link>
            </div>

            <div
              :if={@kpis == []}
              class="ta-leaf col-span-full flex flex-col items-start gap-3 text-sm"
            >
              <p class="text-base-content/70">{gettext("No progression plan yet.")}</p>
              <.link navigate={~p"/teacher/setup"} class="btn btn-primary btn-sm">
                {gettext("Set one up")}
              </.link>
            </div>
          </div>
        </section>
      <% else %>
        <section
          id="academic-year-setup-gate"
          class="mx-auto flex max-w-md flex-col items-center gap-4 py-10 text-center"
        >
          <span class="grid size-14 place-items-center rounded-2xl bg-primary/10 text-primary">
            <.icon name="hero-academic-cap" class="size-7" />
          </span>
          <p class="ta-eyebrow">{gettext("Get started")}</p>
          <h1 class="text-2xl font-bold sm:text-3xl">{gettext("Welcome")}</h1>
          <p class="text-base-content/70">{gettext("Set up your academic year to get started.")}</p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary">
            {gettext("Start setup")}
          </.link>
        </section>
      <% end %>
    </Layouts.app>
    """
  end
end
