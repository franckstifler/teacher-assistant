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
      <section id="teacher-coverage" class="space-y-6">
        <header>
          <p class="ta-eyebrow">{gettext("Coverage")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{@plan.title}</h1>
        </header>

        <div id="coverage-summary" class="ta-leaf flex flex-col gap-4">
          <div class="flex items-end justify-between gap-4">
            <div class="ta-num text-5xl font-semibold leading-none text-primary">
              {round(@coverage.rate * 100)}%
            </div>
            <div class="text-right text-sm text-base-content/65">
              <div class="ta-eyebrow">{gettext("covered")}</div>
              <div class="ta-num mt-1 font-semibold text-base-content">
                {@coverage.covered_hours}h / {@coverage.planned_hours}h
              </div>
            </div>
          </div>
          <.coverage_ribbon rate={@coverage.rate * 100} />
        </div>

        <div class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("Not yet covered")}</h2>
          <ul id="uncovered-entries" class="space-y-2">
            <li
              :for={e <- @uncovered}
              id={"uncovered-#{e.id}"}
              class="ta-leaf flex items-baseline gap-2 text-sm"
            >
              <span class="font-semibold">{e.module}</span>
              <span class="text-base-content/45">·</span>
              <span class="text-base-content/75">{e.lesson_title}</span>
            </li>
            <li
              :if={@uncovered == []}
              class="ta-leaf flex items-center gap-2 text-sm text-base-content/70"
            >
              <.icon name="hero-check-circle" class="size-5 text-success" />
              {gettext("Everything is covered.")}
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
