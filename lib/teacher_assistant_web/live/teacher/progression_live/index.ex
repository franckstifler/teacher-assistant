defmodule TeacherAssistantWeb.Teacher.ProgressionLive.Index do
  use TeacherAssistantWeb, :live_view

  require Ash.Query

  alias TeacherAssistant.Academics.ApcLessonPlan
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.ProgrammeCoverage
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.ProgressionImport
  alias TeacherAssistant.Academics.ProgressionPlan
  alias TeacherAssistant.Academics.TeachingAssignment
  alias TeacherAssistant.Academics.TeachingLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Programme progression"))
     |> assign(:import_previews, %{})
     |> allow_upload(:progression_pdf, accept: ~w(.pdf), max_entries: 1)
     |> load_management_data()
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
          <section
            :if={@personal_workspace? && @assignments == []}
            id="personal-progression-setup-empty"
            class="rounded-md border border-base-300 bg-base-100 p-8 text-center"
          >
            <.icon name="hero-calendar-days" class="mx-auto size-10 text-base-content/30" />
            <p class="mt-3 text-sm text-base-content/60">
              {gettext("Complete your personal setup before creating progression plans.")}
            </p>
            <.link navigate={~p"/teacher/setup"} class="btn btn-primary btn-sm mt-4">
              {gettext("Complete setup")}
            </.link>
          </section>

          <section
            :if={@personal_workspace? && @assignments != []}
            id="personal-progression-management"
            class="rounded-md border border-base-300 bg-base-100 p-5"
          >
            <h2 class="text-base font-semibold">{gettext("Create progression plan")}</h2>
            <.form
              for={@plan_form}
              id="progression-plan-form"
              phx-submit="create_progression_plan"
              class="mt-4 grid gap-4 md:grid-cols-[1fr_10rem_10rem_auto] md:items-end"
            >
              <.input
                field={@plan_form[:assignment_id]}
                type="select"
                label={gettext("Class and subject")}
                options={assignment_options(@assignments)}
              />
              <.input
                field={@plan_form[:weekly_hours]}
                type="number"
                step="0.25"
                label={gettext("Weekly hours")}
              />
              <.input
                field={@plan_form[:annual_hours]}
                type="number"
                step="0.25"
                label={gettext("Annual hours")}
              />
              <.button class="btn btn-primary">
                <.icon name="hero-plus" class="size-4" />
                {gettext("Create")}
              </.button>
            </.form>
          </section>

          <div
            :if={!@personal_workspace? && @plans == []}
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

            <div class="border-b border-base-300 bg-base-200/40 p-5">
              <div class="grid gap-5 xl:grid-cols-[minmax(18rem,24rem)_1fr]">
                <div>
                  <h3 class="flex items-center gap-2 text-sm font-semibold">
                    <.icon name="hero-arrow-up-tray" class="size-4 text-primary" />
                    {gettext("Import PDF progression")}
                  </h3>
                  <p class="mt-1 text-xs text-base-content/60">
                    {gettext(
                      "Upload a Word or Excel exported PDF, review the rows, then save them as weekly entries."
                    )}
                  </p>
                  <.form
                    for={to_form(%{}, as: :progression_import_upload)}
                    id={"progression-import-form-#{plan.id}"}
                    phx-submit="preview_progression_import"
                    phx-value-plan-id={plan.id}
                    class="mt-4 grid gap-3"
                  >
                    <.live_file_input
                      upload={@uploads.progression_pdf}
                      class="file-input file-input-bordered file-input-sm w-full"
                    />
                    <div
                      :if={@uploads.progression_pdf.entries != []}
                      class="text-xs text-base-content/60"
                    >
                      <%= for entry <- @uploads.progression_pdf.entries do %>
                        <span id={"progression-import-upload-#{entry.ref}"}>
                          {entry.client_name}
                        </span>
                      <% end %>
                    </div>
                    <div
                      :if={upload_errors(@uploads.progression_pdf) != []}
                      class="text-xs text-error"
                    >
                      {gettext("Only PDF files can be imported.")}
                    </div>
                    <div>
                      <.button class="btn btn-primary btn-sm">
                        <.icon name="hero-document-arrow-up" class="size-4" />
                        {gettext("Import PDF progression")}
                      </.button>
                    </div>
                  </.form>
                </div>

                <div
                  :if={preview = Map.get(@import_previews, plan.id)}
                  id={"progression-import-review-#{plan.id}"}
                  class="rounded-md border border-base-300 bg-base-100 p-4"
                >
                  <div class="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
                    <div>
                      <h3 class="text-sm font-semibold">{gettext("Review generated rows")}</h3>
                      <p class="mt-1 text-xs text-base-content/60">
                        {gettext(
                          "Duplicate week warnings are informational; saving always appends new entries."
                        )}
                      </p>
                    </div>
                    <span class="badge badge-outline">{length(preview.rows)} rows</span>
                  </div>

                  <.form
                    for={to_form(%{}, as: :progression_import)}
                    id={"progression-import-review-form-#{plan.id}"}
                    phx-submit="save_progression_import"
                    phx-value-plan-id={plan.id}
                    class="mt-4"
                  >
                    <div class="overflow-x-auto">
                      <table class="table table-sm">
                        <thead>
                          <tr>
                            <th>{gettext("Week")}</th>
                            <th>{gettext("Start")}</th>
                            <th>{gettext("End")}</th>
                            <th>{gettext("Title")}</th>
                            <th>{gettext("Content")}</th>
                            <th>{gettext("Hours")}</th>
                            <th>{gettext("Status")}</th>
                          </tr>
                        </thead>
                        <tbody>
                          <tr
                            :for={{row, index} <- Enum.with_index(preview.rows)}
                            id={"progression-import-row-#{plan.id}-#{index}"}
                          >
                            <td>
                              <input
                                name={"progression_import[rows][#{index}][week_number]"}
                                value={row.week_number}
                                type="number"
                                min="1"
                                class="input input-bordered input-sm w-20"
                              />
                            </td>
                            <td>
                              <input
                                name={"progression_import[rows][#{index}][start_date]"}
                                value={date_value(row.start_date)}
                                type="date"
                                class="input input-bordered input-sm w-36"
                              />
                            </td>
                            <td>
                              <input
                                name={"progression_import[rows][#{index}][end_date]"}
                                value={date_value(row.end_date)}
                                type="date"
                                class="input input-bordered input-sm w-36"
                              />
                            </td>
                            <td>
                              <input
                                name={"progression_import[rows][#{index}][title]"}
                                value={row.title}
                                type="text"
                                class="input input-bordered input-sm w-56"
                              />
                            </td>
                            <td>
                              <input
                                name={"progression_import[rows][#{index}][planned_content]"}
                                value={row.planned_content}
                                type="text"
                                class="input input-bordered input-sm w-72"
                              />
                            </td>
                            <td>
                              <input
                                name={"progression_import[rows][#{index}][planned_hours]"}
                                value={decimal_value(row.planned_hours)}
                                type="number"
                                step="0.25"
                                class="input input-bordered input-sm w-24"
                              />
                            </td>
                            <td class="min-w-48">
                              <div
                                :if={row.duplicate?}
                                class="badge badge-warning badge-outline badge-sm"
                              >
                                {gettext("Duplicate week")}
                              </div>
                              <div :for={error <- row.errors} class="mt-1 text-xs text-error">
                                {error}
                              </div>
                              <div
                                :if={!row.duplicate? && row.errors == []}
                                class="badge badge-success badge-outline badge-sm"
                              >
                                {gettext("Ready")}
                              </div>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                    <div class="mt-4 flex justify-end">
                      <.button class="btn btn-primary btn-sm">
                        <.icon name="hero-check" class="size-4" />
                        {gettext("Save reviewed rows")}
                      </.button>
                    </div>
                  </.form>
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

            <div :if={@personal_workspace?} class="border-t border-base-300 p-5">
              <h3 class="text-sm font-semibold">{gettext("Add weekly entry")}</h3>
              <.form
                for={entry_form()}
                id={"progression-entry-form-#{plan.id}"}
                phx-submit="create_progression_entry"
                phx-value-plan-id={plan.id}
                class="mt-3 grid gap-3 lg:grid-cols-[7rem_1fr_1fr_8rem_auto]"
              >
                <.input
                  field={entry_form()[:week_number]}
                  type="number"
                  min="1"
                  label={gettext("Week")}
                />
                <.input field={entry_form()[:title]} label={gettext("Title")} />
                <.input
                  field={entry_form()[:planned_content]}
                  label={gettext("Planned content")}
                />
                <.input
                  field={entry_form()[:planned_hours]}
                  type="number"
                  step="0.25"
                  label={gettext("Hours")}
                />
                <input
                  type="hidden"
                  name="progression_entry[term_id]"
                  value={default_term_id(@terms)}
                />
                <input type="hidden" name="progression_entry[entry_type]" value="lesson" />
                <div class="flex items-end">
                  <.button class="btn btn-secondary">
                    <.icon name="hero-plus" class="size-4" />
                    {gettext("Add")}
                  </.button>
                </div>
              </.form>
            </div>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("create_progression_plan", %{"progression_plan" => params}, socket) do
    assignment = Enum.find(socket.assigns.assignments, &(&1.id == params["assignment_id"]))

    result =
      if assignment do
        PersonalWorkspace.create_progression_plan(socket.assigns.scope, %{
          "academic_year_id" => assignment.classroom.academic_year_id,
          "classroom_id" => assignment.classroom_id,
          "level_option_subject_id" => assignment.level_option_subject_id,
          "weekly_hours" => params["weekly_hours"],
          "annual_hours" => params["annual_hours"]
        })
      else
        {:error, :assignment_required}
      end

    case result do
      {:ok, _plan} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Progression plan created"))
         |> load_management_data()
         |> load_plans()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Progression plan could not be created"))}
    end
  end

  def handle_event("preview_progression_import", %{"plan-id" => plan_id}, socket) do
    results =
      consume_uploaded_entries(socket, :progression_pdf, fn %{path: path}, _entry ->
        {:ok, ProgressionImport.preview_rows(socket.assigns.scope, plan_id, path)}
      end)

    case results do
      [{:ok, preview}] ->
        {:noreply,
         socket
         |> assign(:import_previews, Map.put(socket.assigns.import_previews, plan_id, preview))
         |> put_flash(:info, gettext("Progression rows generated for review"))}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, import_error_message(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, gettext("Choose a PDF file to import"))}
    end
  end

  def handle_event(
        "save_progression_import",
        %{"plan-id" => plan_id, "progression_import" => %{"rows" => rows}},
        socket
      ) do
    rows =
      rows
      |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
      |> Enum.map(&elem(&1, 1))

    case ProgressionImport.save_rows(socket.assigns.scope, plan_id, rows) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(:import_previews, Map.delete(socket.assigns.import_previews, plan_id))
         |> put_flash(:info, gettext("Progression entries imported"))
         |> load_plans()}

      {:error, {:invalid_rows, invalid_rows}} ->
        preview = %{rows: invalid_rows}

        {:noreply,
         socket
         |> assign(:import_previews, Map.put(socket.assigns.import_previews, plan_id, preview))
         |> put_flash(:error, gettext("Fix the highlighted rows before saving"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, import_error_message(reason))}
    end
  end

  def handle_event(
        "create_progression_entry",
        %{"plan-id" => plan_id, "progression_entry" => params},
        socket
      ) do
    case PersonalWorkspace.create_progression_entry(socket.assigns.scope, plan_id, params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Progression entry created"))
         |> load_plans()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Progression entry could not be created"))}
    end
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

  defp load_management_data(socket) do
    personal_workspace? = personal_workspace?(socket.assigns.current_scope)

    assignments =
      if personal_workspace? do
        TeachingAssignment
        |> Ash.Query.filter(teacher_id == ^socket.assigns.current_user.id)
        |> Ash.Query.load(
          level_option_subject: [:subject],
          classroom: [level_option: [:full_name]]
        )
        |> Ash.read!(scope: socket.assigns.scope)
      else
        []
      end

    terms =
      case socket.assigns.current_scope.current_academic_year do
        nil ->
          []

        year ->
          year
          |> Ash.load!(:terms, scope: socket.assigns.scope)
          |> Map.get(:terms, [])
      end

    socket
    |> assign(:personal_workspace?, personal_workspace?)
    |> assign(:assignments, assignments)
    |> assign(:terms, terms)
    |> assign(
      :plan_form,
      to_form(%{"weekly_hours" => "", "annual_hours" => ""}, as: :progression_plan)
    )
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
      as: :teaching_log,
      id: "teaching-log-#{entry.id}"
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
      as: :apc_lesson_plan,
      id: "apc-lesson-plan-#{entry.id}"
    )
  end

  defp entry_form do
    to_form(
      %{
        "week_number" => "",
        "title" => "",
        "planned_content" => "",
        "planned_hours" => "",
        "term_id" => "",
        "entry_type" => "lesson"
      },
      as: :progression_entry
    )
  end

  defp assignment_options(assignments) do
    Enum.map(assignments, fn assignment ->
      {assignment_label(assignment), assignment.id}
    end)
  end

  defp assignment_label(assignment) do
    subject = assignment.level_option_subject.subject.name
    classroom = assignment.classroom.level_option.full_name
    "#{classroom} · #{subject}"
  end

  defp default_term_id([term | _]), do: term.id
  defp default_term_id(_terms), do: nil

  defp personal_workspace?(%{current_workspace_type: :personal_teacher}), do: true
  defp personal_workspace?(_scope), do: false

  defp value(nil, _field), do: ""
  defp value(record, field), do: Map.get(record, field) || ""

  defp date_value(nil), do: ""
  defp date_value(%Date{} = date), do: Date.to_iso8601(date)
  defp date_value(value), do: value

  defp decimal_value(nil), do: ""
  defp decimal_value(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp decimal_value(value), do: value

  defp import_error_message(:pdftotext_missing) do
    gettext("PDF extraction requires Poppler. Install the pdftotext command on the server.")
  end

  defp import_error_message(:empty_pdf), do: gettext("The PDF did not contain readable text.")

  defp import_error_message(:no_progression_rows),
    do: gettext("No progression rows were found in the PDF.")

  defp import_error_message(:plan_not_found),
    do: gettext("Progression plan could not be accessed.")

  defp import_error_message(_reason), do: gettext("Progression PDF could not be imported.")
end
