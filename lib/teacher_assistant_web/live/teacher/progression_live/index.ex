defmodule TeacherAssistantWeb.Teacher.ProgressionLive.Index do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  alias TeacherAssistant.Academics.ApcLessonPlan
  alias TeacherAssistant.Academics.ProgrammeCoverage
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.ProgressionPlan
  alias TeacherAssistant.Academics.TeachingLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Programme progression"))
     |> load_plans()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <.header>
          {gettext("Programme progression")}
          <:subtitle>
            {gettext("Track weekly progression, actual taught hours, and APC lesson structures.")}
          </:subtitle>
        </.header>

        <div id="teacher-progression-workspace" class="space-y-5">
          <div
            :if={@plans == []}
            class="rounded-md border border-base-300 bg-base-100 p-8 text-center"
          >
            <.icon name="hero-calendar-days" class="mx-auto size-10 text-base-content/30" />
            <p class="mt-3 text-sm text-base-content/60">
              {gettext("No progression plan has been assigned to you yet.")}
            </p>
          </div>

          <section
            :for={plan <- @plans}
            id={"progression-plan-#{plan.id}"}
            class="rounded-md border border-base-300 bg-base-100"
          >
            <div class="flex flex-col gap-3 border-b border-base-300 p-5 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 class="text-lg font-semibold">{plan_title(plan)}</h2>
                <p class="mt-1 text-sm text-base-content/60">
                  {gettext("Weekly hours")}: {Decimal.to_string(plan.weekly_hours)}
                  <span class="px-2">·</span>
                  {gettext("Annual hours")}: {Decimal.to_string(plan.annual_hours)}
                </p>
              </div>
              <div class="stats stats-horizontal border border-base-300 shadow-none">
                <div class="stat px-4 py-2">
                  <div class="stat-title text-xs">{gettext("Coverage")}</div>
                  <div id={"coverage-rate-#{plan.id}"} class="stat-value text-xl">
                    {coverage(plan).rate |> Decimal.to_string()}%
                  </div>
                </div>
                <div class="stat px-4 py-2">
                  <div class="stat-title text-xs">{gettext("Taught")}</div>
                  <div class="stat-value text-xl">
                    {coverage(plan).taught_hours |> Decimal.to_string()}h
                  </div>
                </div>
              </div>
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Week")}</th>
                    <th>{gettext("Planned lesson")}</th>
                    <th>{gettext("Teaching log")}</th>
                    <th>{gettext("APC structure")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={plan.entries == []}>
                    <td colspan="4" class="py-8 text-center text-sm text-base-content/60">
                      {gettext("No progression entries are available for this plan.")}
                    </td>
                  </tr>
                  <tr :for={entry <- plan.entries} id={"progression-entry-#{entry.id}"}>
                    <td class="font-medium">{entry.week_number}</td>
                    <td class="min-w-64">
                      <div class="font-medium">{entry.title}</div>
                      <div class="mt-1 text-xs text-base-content/60">
                        {entry.planned_content}
                      </div>
                      <div class="mt-2">
                        <span class="badge badge-outline badge-sm">
                          {Decimal.to_string(entry.planned_hours)}h planned
                        </span>
                      </div>
                    </td>
                    <td class="min-w-80">
                      <.form
                        for={log_form(entry)}
                        id={"teaching-log-form-#{entry.id}"}
                        phx-submit="save_teaching_log"
                        phx-value-entry-id={entry.id}
                        class="grid gap-2"
                      >
                        <div class="grid gap-2 sm:grid-cols-2">
                          <.input
                            field={log_form(entry)[:taught_on]}
                            type="date"
                            label={gettext("Date")}
                          />
                          <.input
                            field={log_form(entry)[:taught_hours]}
                            type="number"
                            step="0.25"
                            label={gettext("Hours")}
                          />
                        </div>
                        <.input field={log_form(entry)[:notes]} type="text" label={gettext("Notes")} />
                        <div class="flex justify-end">
                          <.button class="btn-sm" variant="primary">
                            <.icon name="hero-check" class="size-4" />
                            {gettext("Log")}
                          </.button>
                        </div>
                      </.form>
                    </td>
                    <td class="min-w-[28rem]">
                      <.form
                        for={apc_form(entry)}
                        id={"apc-lesson-form-#{entry.id}"}
                        phx-submit="save_apc_lesson"
                        phx-value-entry-id={entry.id}
                        class="grid gap-2"
                      >
                        <.input
                          field={apc_form(entry)[:competence]}
                          type="text"
                          label={gettext("Competence")}
                        />
                        <div class="grid gap-2 sm:grid-cols-2">
                          <.input
                            field={apc_form(entry)[:prerequisites]}
                            type="text"
                            label={gettext("Prerequisites")}
                          />
                          <.input
                            field={apc_form(entry)[:duration_minutes]}
                            type="number"
                            label={gettext("Minutes")}
                          />
                        </div>
                        <.input
                          field={apc_form(entry)[:situation_problem]}
                          type="text"
                          label={gettext("Situation-problem")}
                        />
                        <.input
                          field={apc_form(entry)[:learning_activities]}
                          type="text"
                          label={gettext("Activities")}
                        />
                        <div class="grid gap-2 sm:grid-cols-3">
                          <.input
                            field={apc_form(entry)[:resources]}
                            type="text"
                            label={gettext("Resources")}
                          />
                          <.input
                            field={apc_form(entry)[:evaluation]}
                            type="text"
                            label={gettext("Evaluation")}
                          />
                          <.input
                            field={apc_form(entry)[:remediation]}
                            type="text"
                            label={gettext("Remediation")}
                          />
                        </div>
                        <div class="flex justify-end">
                          <.button class="btn-sm" variant="primary">
                            <.icon name="hero-document-check" class="size-4" />
                            {gettext("Save APC")}
                          </.button>
                        </div>
                      </.form>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event(
        "save_teaching_log",
        %{"entry-id" => entry_id, "teaching_log" => params},
        socket
      ) do
    params = Map.put(params, "progression_entry_id", entry_id)

    case Ash.create(TeachingLog, params, scope: socket.assigns.scope) do
      {:ok, _log} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Teaching log saved successfully"))
         |> load_plans()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  def handle_event(
        "save_apc_lesson",
        %{"entry-id" => entry_id, "apc_lesson_plan" => params},
        socket
      ) do
    entry =
      ProgressionEntry
      |> Ash.Query.filter(id == ^entry_id)
      |> Ash.Query.load(:apc_lesson_plans)
      |> Ash.read_one!(scope: socket.assigns.scope)

    result =
      case entry.apc_lesson_plans do
        [lesson | _] ->
          lesson
          |> Ash.Changeset.for_update(:update, params, scope: socket.assigns.scope)
          |> Ash.update()

        [] ->
          Ash.create(ApcLessonPlan, Map.put(params, "progression_entry_id", entry_id),
            scope: socket.assigns.scope
          )
      end

    case result do
      {:ok, _lesson} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("APC lesson structure saved successfully"))
         |> load_plans()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  defp load_plans(socket) do
    plans =
      ProgressionPlan
      |> Ash.Query.filter(teacher_id == ^socket.assigns.current_user.id)
      |> Ash.Query.load([
        :teacher,
        classroom: [level_option: [:level, :option]],
        level_option_subject: [:subject],
        entries: [:teaching_logs, :apc_lesson_plans]
      ])
      |> Ash.read!(scope: socket.assigns.scope)
      |> Enum.map(&sort_entries/1)

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

  defp plan_title(plan) do
    classroom =
      "#{plan.classroom.level_option.level.name} #{plan.classroom.level_option.option.name}"

    subject = plan.level_option_subject.subject.name

    "#{classroom} · #{subject}"
  end

  defp log_form(entry) do
    log = List.first(entry.teaching_logs)

    to_form(
      %{
        "taught_on" =>
          if(log, do: Date.to_iso8601(log.taught_on), else: Date.to_iso8601(Date.utc_today())),
        "taught_hours" => if(log, do: Decimal.to_string(log.taught_hours), else: ""),
        "notes" => if(log, do: log.notes, else: "")
      },
      as: :teaching_log
    )
  end

  defp apc_form(entry) do
    lesson = List.first(entry.apc_lesson_plans)

    to_form(
      %{
        "competence" => value(lesson, :competence),
        "prerequisites" => value(lesson, :prerequisites),
        "situation_problem" => value(lesson, :situation_problem),
        "learning_activities" => value(lesson, :learning_activities),
        "resources" => value(lesson, :resources),
        "evaluation" => value(lesson, :evaluation),
        "remediation" => value(lesson, :remediation),
        "duration_minutes" => value(lesson, :duration_minutes)
      },
      as: :apc_lesson_plan
    )
  end

  defp value(nil, _field), do: ""
  defp value(record, field), do: Map.get(record, field) || ""
end
