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

        year = Academics.current_academic_year(ws)
        sequences = (year && Academics.list_sequences(year)) || []
        per_entry = Map.new(coverage.per_entry, fn pe -> {pe.entry_id, pe} end)

        {:ok,
         assign(socket,
           plan: plan,
           coverage: coverage,
           uncovered: uncovered,
           sequences: sequences,
           per_entry: per_entry
         )}

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
        <.page_header eyebrow={gettext("Coverage")} title={@plan.title} />

        <div id="coverage-summary" class="ta-leaf flex flex-col gap-4">
          <div class="flex items-end justify-between gap-4">
            <.stat
              label={gettext("covered")}
              value={"#{round(@coverage.rate * 100)}"}
              suffix="%"
              tone={:primary}
            />
            <div class="text-right text-sm text-base-content/65">
              <div class="ta-num mt-1 font-semibold text-base-content">
                {@coverage.covered_hours}h / {@coverage.planned_hours}h
              </div>
            </div>
          </div>
          <.coverage_ribbon rate={@coverage.rate * 100} />
        </div>

        <div :if={map_size(@coverage.by_sequence) > 0} class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("By séquence")}</h2>
          <ul id="coverage-by-sequence" class="space-y-2">
            <li
              :for={s <- @sequences}
              :if={@coverage.by_sequence[s.id]}
              id={"coverage-seq-#{s.id}"}
              class="ta-leaf flex items-center gap-3 text-sm"
            >
              <span class="w-24 shrink-0 font-semibold">{gettext("Séquence")} {s.number}</span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-primary"
                  style={"width: #{round(@coverage.by_sequence[s.id].rate * 100)}%"}
                >
                </div>
              </div>
              <span class="ta-num w-24 shrink-0 text-right text-base-content/70">
                {@coverage.by_sequence[s.id].covered}h / {@coverage.by_sequence[s.id].planned}h
              </span>
            </li>
            <li
              :if={@coverage.by_sequence[nil]}
              id="coverage-seq-none"
              class="ta-leaf flex items-center gap-3 text-sm"
            >
              <span class="w-24 shrink-0 font-semibold text-base-content/60">
                {gettext("Sans séquence")}
              </span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-primary"
                  style={"width: #{round(@coverage.by_sequence[nil].rate * 100)}%"}
                >
                </div>
              </div>
              <span class="ta-num w-24 shrink-0 text-right text-base-content/70">
                {@coverage.by_sequence[nil].covered}h / {@coverage.by_sequence[nil].planned}h
              </span>
            </li>
          </ul>
        </div>

        <div class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("Not yet covered")}</h2>
          <ul :if={@uncovered != []} id="uncovered-entries" class="space-y-2">
            <li
              :for={e <- @uncovered}
              id={"uncovered-#{e.id}"}
              class="ta-leaf flex items-baseline gap-2 text-sm"
            >
              <span class="font-semibold">{e.module}</span>
              <span class="text-base-content/45">·</span>
              <span class="flex-1 text-base-content/75">{e.lesson_title}</span>
              <span :if={@per_entry[e.id]} class="ta-num shrink-0 text-base-content/60">
                {@per_entry[e.id].covered}h / {@per_entry[e.id].planned}h
              </span>
            </li>
          </ul>
          <.empty_state
            :if={@uncovered == []}
            icon="hero-check-circle"
            title={gettext("Everything is covered.")}
          />
        </div>
      </section>
    </Layouts.app>
    """
  end
end
