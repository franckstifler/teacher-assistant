defmodule TeacherAssistantWeb.Teacher.CoverageLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => id}, _session, socket) do
    {:ok, plan} = Academics.get_progression_plan(id)
    coverage = Academics.coverage_for_plan(plan)
    entries = Academics.list_progression_entries(plan)

    logged_ids =
      Academics.list_logs_for_plan(plan) |> Enum.map(& &1.progression_entry_id) |> MapSet.new()

    uncovered = Enum.reject(entries, &MapSet.member?(logged_ids, &1.id))

    {:ok, assign(socket, plan: plan, coverage: coverage, uncovered: uncovered)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-coverage" class="p-4 space-y-4">
        <h1 class="text-xl font-semibold">{@plan.title} — {gettext("Coverage")}</h1>
        <div id="coverage-summary" class="card bg-base-100 shadow p-4">
          <div class="text-3xl font-bold">{round(@coverage.rate * 100)}%</div>
          <div class="text-sm opacity-70">
            {@coverage.covered_hours}h / {@coverage.planned_hours}h {gettext("covered")}
          </div>
        </div>
        <div>
          <h2 class="font-medium mb-2">{gettext("Not yet covered")}</h2>
          <ul id="uncovered-entries" class="space-y-1">
            <li :for={e <- @uncovered} id={"uncovered-#{e.id}"} class="text-sm">
              {e.module} · {e.lesson_title}
            </li>
            <li :if={@uncovered == []} class="text-sm opacity-70">
              {gettext("Everything is covered.")}
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
