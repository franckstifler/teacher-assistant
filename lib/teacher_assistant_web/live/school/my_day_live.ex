defmodule TeacherAssistantWeb.School.MyDayLive do
  @moduledoc """
  Enseignant → Ma journée (spec G, V01/V03): today's slots with their roll-call
  status, and this week's missed roll calls. The teaching space's home.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Curriculum}
  alias TeacherAssistant.Academics.Reference

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Curriculum.list_units_for_scope(scope) != [] do
      user = scope.current_user
      today = Reference.today()
      now = Reference.now()

      {:ok,
       assign(socket,
         today: today,
         slots: Attendance.teacher_day(scope, user, today, now),
         missed: Attendance.teacher_missed_this_week(scope, user, today, now)
       )}
    else
      {:ok, push_navigate(socket, to: space_home(scope))}
    end
  end

  defp space_home(%{capabilities: %{space: %{home: home}}}) when home != "/school/today", do: home
  defp space_home(_scope), do: ~p"/school/classes"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-day" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Enseignant")} title={gettext("Ma journée")}>
          <:actions>
            <span class="ta-num inline-flex items-center rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold text-base-content/70">
              {Calendar.strftime(@today, "%d/%m/%Y")}
            </span>
          </:actions>
        </.page_header>

        <div :if={@slots == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={gettext("Pas de cours aujourd'hui")} />
        </div>

        <ul :if={@slots != []} id="today-slots" class="flex flex-col gap-2">
          <li :for={slot <- @slots} id={"slot-#{slot.class_group.id}-#{slot.period.id}"}>
            <.link
              :if={slot.status != :upcoming}
              navigate={~p"/school/classes/#{slot.class_group.id}/attendance/#{slot.period.id}"}
              class="ta-leaf flex items-center gap-3 transition hover:border-primary/50 hover:shadow-sm"
            >
              <.slot_line slot={slot} />
            </.link>
            <div :if={slot.status == :upcoming} class="ta-leaf flex items-center gap-3 opacity-80">
              <.slot_line slot={slot} />
            </div>
          </li>
        </ul>

        <div :if={@missed != []} id="missed-this-week" class="flex flex-col gap-2">
          <h2 class="ta-eyebrow">{gettext("Appels manquants cette semaine")}</h2>
          <.link
            :for={m <- @missed}
            id={"missed-#{m.class_group.id}-#{m.period.id}-#{m.date}"}
            navigate={
              ~p"/school/classes/#{m.class_group.id}/attendance/#{m.period.id}?date=#{Date.to_iso8601(m.date)}"
            }
            class="ta-leaf flex items-center justify-between gap-3 text-sm transition hover:border-warning/60"
          >
            <span>
              <span class="ta-num font-semibold">{Calendar.strftime(m.date, "%d/%m")}</span>
              · {m.period.label} · {m.class_group.label} · {m.subject}
            </span>
            <span class="badge badge-warning badge-sm">{gettext("Non fait")}</span>
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :slot, :map, required: true

  defp slot_line(assigns) do
    ~H"""
    <div class="ta-num w-24 shrink-0 text-xs text-base-content/70">
      <p class="font-semibold text-base-content">{@slot.period.label}</p>
      <p>{hm(@slot.period.start_time)}–{hm(@slot.period.end_time)}</p>
    </div>
    <div class="min-w-0 flex-1">
      <p class="font-semibold">{@slot.class_group.label}</p>
      <p class="truncate text-sm text-base-content/70">{@slot.subject}</p>
    </div>
    <.status_tag status={@slot.status} absent={@slot.absent} />
    """
  end

  attr :status, :atom, required: true
  attr :absent, :integer, required: true

  defp status_tag(%{status: :done} = assigns),
    do: ~H"""
    <span class="badge badge-success badge-sm">
      {gettext("Fait · %{count} abs.", count: @absent)}
    </span>
    """

  defp status_tag(%{status: :in_progress} = assigns),
    do: ~H|<span class="badge badge-info badge-sm">{gettext("En cours")}</span>|

  defp status_tag(%{status: :missed} = assigns),
    do: ~H|<span class="badge badge-warning badge-sm">{gettext("Non fait")}</span>|

  defp status_tag(%{status: :upcoming} = assigns),
    do: ~H|<span class="badge badge-ghost badge-sm">{gettext("À venir")}</span>|

  defp hm(time), do: Calendar.strftime(time, "%H:%M")
end
