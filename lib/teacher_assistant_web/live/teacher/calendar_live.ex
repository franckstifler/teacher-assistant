defmodule TeacherAssistantWeb.Teacher.CalendarLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics.PedagogicalCalendar
  alias TeacherAssistant.Academics.TeachingLog

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, gettext("Pedagogical calendar"))
     |> assign(:mode, :today)
     |> assign(:selected_date, today)
     |> load_activities()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="teacher-calendar" class="space-y-6">
        <.header>
          {gettext("Pedagogical calendar")}
          <:subtitle>
            {gettext(
              "Follow planned lessons, delayed activities, and taught hours from your progression sheets."
            )}
          </:subtitle>
        </.header>

        <section class="rounded-md border border-base-300 bg-base-100 p-4">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="join">
              <button
                id="calendar-mode-today"
                type="button"
                phx-click="set_mode"
                phx-value-mode="today"
                class={["btn join-item btn-sm", @mode == :today && "btn-primary"]}
              >
                {gettext("Today")}
              </button>
              <button
                id="calendar-mode-week"
                type="button"
                phx-click="set_mode"
                phx-value-mode="week"
                class={["btn join-item btn-sm", @mode == :week && "btn-primary"]}
              >
                {gettext("This week")}
              </button>
              <button
                id="calendar-mode-month"
                type="button"
                phx-click="set_mode"
                phx-value-mode="month"
                class={["btn join-item btn-sm", @mode == :month && "btn-primary"]}
              >
                {gettext("Calendar")}
              </button>
            </div>

            <div class="flex items-center gap-3 text-sm text-base-content/60">
              <.icon name="hero-calendar-days" class="size-4" />
              <span>{date_scope_label(@mode, @selected_date)}</span>
            </div>
          </div>
        </section>

        <section :if={@mode != :month} id={"calendar-#{@mode}-view"} class="grid gap-4">
          <div
            :if={@activities == []}
            id="calendar-empty"
            class="rounded-md border border-dashed border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/60"
          >
            {gettext("No pedagogical activities are due in this view.")}
          </div>

          <.activity_card :for={activity <- @activities} activity={activity} />
        </section>

        <section :if={@mode == :month} id="calendar-month-view" class="space-y-4">
          <div
            :if={@activities == []}
            id="calendar-empty"
            class="rounded-md border border-dashed border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/60"
          >
            {gettext("No pedagogical activities are planned for this month.")}
          </div>

          <div
            :for={{date, activities} <- grouped_by_day(@activities)}
            id={"calendar-day-#{Date.to_iso8601(date)}"}
            class="rounded-md border border-base-300 bg-base-100"
          >
            <div class="border-b border-base-300 px-4 py-3">
              <h2 class="text-sm font-semibold">{Calendar.strftime(date, "%A, %B %d")}</h2>
            </div>
            <div class="grid gap-3 p-4">
              <.activity_card :for={activity <- activities} activity={activity} />
            </div>
          </div>
        </section>

        <section
          :if={@unscheduled != []}
          id="calendar-unscheduled"
          class="rounded-md border border-base-300 bg-base-100 p-4"
        >
          <h2 class="text-sm font-semibold">{gettext("Unscheduled")}</h2>
          <div class="mt-3 grid gap-3">
            <.activity_card :for={activity <- @unscheduled} activity={activity} />
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :activity, :map, required: true

  defp activity_card(assigns) do
    ~H"""
    <article
      id={"calendar-activity-#{@activity.entry_id}"}
      class="rounded-md border border-base-300 bg-base-100 p-4 shadow-sm"
    >
      <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <span id={"calendar-status-#{@activity.entry_id}"} class={status_badge(@activity.status)}>
              {status_label(@activity.status)}
            </span>
            <span class="badge badge-outline badge-sm">{entry_type_label(@activity.entry_type)}</span>
            <span :if={@activity.week_number} class="badge badge-ghost badge-sm">
              {gettext("Week")} {@activity.week_number}
            </span>
          </div>
          <h2 class="mt-2 text-base font-semibold">{@activity.title}</h2>
          <p class="mt-1 text-sm text-base-content/60">{@activity.plan_label}</p>
          <p :if={@activity.planned_content} class="mt-2 text-sm">{@activity.planned_content}</p>
          <div class="mt-3 flex flex-wrap gap-2 text-xs text-base-content/60">
            <span>{date_range(@activity)}</span>
            <span>
              {Decimal.to_string(@activity.taught_hours)}h / {Decimal.to_string(
                @activity.planned_hours
              )}h
            </span>
            <span :if={@activity.has_apc?} class="text-success">{gettext("APC ready")}</span>
          </div>
        </div>

        <.link
          navigate={~p"/teacher/progression"}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-4" />
          {gettext("Full plan")}
        </.link>
      </div>

      <.form
        for={log_form(@activity)}
        id={"calendar-log-form-#{@activity.entry_id}"}
        phx-submit="save_teaching_log"
        phx-value-entry-id={@activity.entry_id}
        class="mt-4 grid gap-3 border-t border-base-300 pt-4 md:grid-cols-[10rem_8rem_1fr_auto] md:items-end"
      >
        <.input field={log_form(@activity)[:taught_on]} type="date" label={gettext("Taught on")} />
        <.input
          field={log_form(@activity)[:taught_hours]}
          type="number"
          step="0.25"
          label={gettext("Hours")}
        />
        <.input field={log_form(@activity)[:notes]} type="text" label={gettext("Notes")} />
        <.button class="btn btn-primary btn-sm">
          <.icon name="hero-check" class="size-4" />
          {gettext("Log")}
        </.button>
      </.form>
    </article>
    """
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply,
     socket
     |> assign(:mode, parse_mode(mode))
     |> load_activities()}
  end

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
         |> put_flash(:info, gettext("Teaching activity logged"))
         |> load_activities()}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  defp load_activities(socket) do
    {:ok, activities} =
      PedagogicalCalendar.list_activities(socket.assigns.scope, %{
        mode: socket.assigns.mode,
        date: socket.assigns.selected_date
      })

    {:ok, unscheduled} =
      PedagogicalCalendar.list_activities(socket.assigns.scope, %{
        mode: :all,
        date: socket.assigns.selected_date
      })

    assign(socket,
      activities: activities,
      unscheduled: Enum.filter(unscheduled, &(is_nil(&1.start_date) or is_nil(&1.end_date)))
    )
  end

  defp parse_mode("week"), do: :week
  defp parse_mode("month"), do: :month
  defp parse_mode(_mode), do: :today

  defp grouped_by_day(activities) do
    activities
    |> Enum.reject(&(is_nil(&1.start_date) or is_nil(&1.end_date)))
    |> Enum.group_by(& &1.start_date)
    |> Enum.sort_by(fn {date, _activities} -> date end)
  end

  defp log_form(activity) do
    to_form(
      %{
        "taught_on" => Date.to_iso8601(Date.utc_today()),
        "taught_hours" => "",
        "notes" => ""
      },
      as: :teaching_log,
      id: "calendar-teaching-log-#{activity.entry_id}"
    )
  end

  defp status_label(:completed), do: gettext("Completed")
  defp status_label(:partially_taught), do: gettext("Partially taught")
  defp status_label(:late), do: gettext("Late")
  defp status_label(:due_today), do: gettext("Due today")
  defp status_label(:planned), do: gettext("Planned")
  defp status_label(_status), do: gettext("Planned")

  defp status_badge(:completed), do: "badge badge-success badge-sm"
  defp status_badge(:partially_taught), do: "badge badge-info badge-sm"
  defp status_badge(:late), do: "badge badge-error badge-sm"
  defp status_badge(:due_today), do: "badge badge-warning badge-sm"
  defp status_badge(:planned), do: "badge badge-outline badge-sm"
  defp status_badge(_status), do: "badge badge-outline badge-sm"

  defp entry_type_label(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp date_range(%{start_date: nil}), do: gettext("Unscheduled")
  defp date_range(%{end_date: nil}), do: gettext("Unscheduled")

  defp date_range(%{start_date: start_date, end_date: end_date}) do
    if start_date == end_date do
      Calendar.strftime(start_date, "%b %d")
    else
      "#{Calendar.strftime(start_date, "%b %d")} - #{Calendar.strftime(end_date, "%b %d")}"
    end
  end

  defp date_scope_label(:today, date), do: Calendar.strftime(date, "%A, %B %d")

  defp date_scope_label(:week, date) do
    start_date = Date.add(date, -(Date.day_of_week(date) - 1))
    end_date = Date.add(start_date, 6)
    "#{Calendar.strftime(start_date, "%B %d")} - #{Calendar.strftime(end_date, "%B %d")}"
  end

  defp date_scope_label(:month, date), do: Calendar.strftime(date, "%B %Y")
end
