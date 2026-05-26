defmodule TeacherAssistantWeb.Reports.ProgrammeCoverageLive.Index do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.ProgrammeCoverage
  alias TeacherAssistant.Academics.ProgressionPlan

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Programme coverage"))
     |> load_plans()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>
          {gettext("Programme coverage")}
          <:subtitle>
            {gettext("Term and yearly programme coverage from progression plans and teaching logs.")}
          </:subtitle>
        </.header>

        <section
          id="programme-coverage-table"
          class="overflow-x-auto rounded-md border border-base-300 bg-base-100"
        >
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Classroom")}</th>
                <th>{gettext("Subject")}</th>
                <th>{gettext("Teacher")}</th>
                <th>{gettext("Planned")}</th>
                <th>{gettext("Taught")}</th>
                <th>{gettext("Coverage")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@plans == []}>
                <td colspan="6" class="py-8 text-center text-sm text-base-content/60">
                  {gettext("No progression plans are available yet.")}
                </td>
              </tr>
              <tr :for={plan <- @plans} id={"coverage-row-#{plan.id}"}>
                <td class="font-medium">{classroom_name(plan)}</td>
                <td>{plan.level_option_subject.subject.name}</td>
                <td>{plan.teacher.email}</td>
                <td>{Decimal.to_string(coverage(plan).planned_hours)}h</td>
                <td>{Decimal.to_string(coverage(plan).taught_hours)}h</td>
                <td>
                  <span id={"coverage-rate-#{plan.id}"} class={coverage_badge(coverage(plan).rate)}>
                    {Decimal.to_string(coverage(plan).rate)}%
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp load_plans(socket) do
    plans =
      ProgressionPlan
      |> Ash.Query.load([
        :teacher,
        classroom: [level_option: [:level, :option]],
        level_option_subject: [:subject],
        entries: [:teaching_logs]
      ])
      |> Ash.read!(scope: socket.assigns.scope)
      |> Enum.map(&sort_entries/1)
      |> Enum.sort_by(&classroom_name/1)

    assign(socket, :plans, plans)
  end

  defp sort_entries(plan) do
    Map.put(plan, :entries, Enum.sort_by(plan.entries, &(&1.week_number || 0)))
  end

  defp coverage(plan) do
    plan.entries
    |> Enum.map(fn entry ->
      %{
        planned_hours: entry.planned_hours,
        taught_hours:
          Enum.reduce(entry.teaching_logs, Decimal.new("0"), fn log, total ->
            Decimal.add(total, log.taught_hours)
          end)
      }
    end)
    |> ProgrammeCoverage.summarize()
  end

  defp classroom_name(plan) do
    "#{plan.classroom.level_option.level.name} #{plan.classroom.level_option.option.name}"
  end

  defp coverage_badge(rate) do
    cond do
      Decimal.compare(rate, Decimal.new("90")) in [:gt, :eq] -> "badge badge-success badge-sm"
      Decimal.compare(rate, Decimal.new("70")) in [:gt, :eq] -> "badge badge-warning badge-sm"
      true -> "badge badge-error badge-sm"
    end
  end
end
