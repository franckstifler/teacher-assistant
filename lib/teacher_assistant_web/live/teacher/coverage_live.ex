defmodule TeacherAssistantWeb.Teacher.CoverageLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_plan(id, ws) do
      {:ok, plan} ->
        coverage = Academics.coverage_for_plan(plan)
        entries = Academics.list_progression_entries(plan)

        covered_ids =
          coverage.per_entry
          |> Enum.filter(fn pe -> Decimal.compare(pe.covered, pe.planned) != :lt end)
          |> MapSet.new(& &1.entry_id)

        uncovered = Enum.reject(entries, &MapSet.member?(covered_ids, &1.id))

        {:ok, assign(socket, plan: plan, coverage: coverage, uncovered: uncovered)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Plan not found"))
         |> push_navigate(to: ~p"/teacher")}
    end
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
