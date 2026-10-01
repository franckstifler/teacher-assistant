defmodule TeacherAssistantWeb.School.MyDayLive do
  @moduledoc """
  Enseignant → Ma journée (spec G, V01/V03): today's slots with their roll-call
  status beside the roll call of the selected slot (`?slot=<class>-<period>`),
  and this week's missed roll calls. The teaching space's home.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Curriculum}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.School.RollCall

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Curriculum.list_units_for_scope(scope) != [] do
      {:ok, socket |> assign(today: Reference.today(), roll: nil, selected: nil) |> load_day()}
    else
      {:ok, push_navigate(socket, to: space_home(scope))}
    end
  end

  defp space_home(%{capabilities: %{space: %{home: home}}}) when home != "/school/today", do: home
  defp space_home(_scope), do: ~p"/school/classes"

  defp load_day(socket) do
    %{current_scope: scope, today: today} = socket.assigns
    now = Reference.now()
    user = scope.current_user

    assign(socket,
      now: now,
      slots: Attendance.teacher_day(scope, user, today, now),
      day_off: Attendance.day_off(scope, today),
      missed: Attendance.teacher_missed_this_week(scope, user, today, now)
    )
  end

  def handle_params(params, _uri, socket) do
    %{slots: slots, current_scope: scope, today: today} = socket.assigns

    case pick_slot(slots, params["slot"]) do
      nil ->
        {:noreply, assign(socket, selected: nil, roll: nil)}

      slot ->
        roll =
          case RollCall.open(scope, slot.class_group.id, slot.period.id, today) do
            {:ok, roll} -> roll
            {:error, _} -> nil
          end

        {:noreply, assign(socket, selected: slot_key(slot), roll: roll)}
    end
  end

  # The asked slot when it can be called (not upcoming), else the one in
  # progress, else the first missed, else the first done.
  defp pick_slot(slots, key) do
    callable = Enum.reject(slots, &(&1.status == :upcoming))

    Enum.find(callable, &(slot_key(&1) == key)) ||
      Enum.find(callable, &(&1.status == :in_progress)) ||
      Enum.find(callable, &(&1.status == :missed)) ||
      List.first(callable)
  end

  defp slot_key(slot), do: "#{slot.class_group.id}-#{slot.period.id}"

  def handle_event("set", %{"enrollment_id" => id, "status" => status}, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.set(&1, id, status)))}

  def handle_event("record", _params, %{assigns: %{roll: %{}}} = socket) do
    case RollCall.record(socket.assigns.current_scope, socket.assigns.roll) do
      {:ok, roll} ->
        {:noreply,
         socket
         |> assign(:roll, roll)
         |> load_day()
         |> put_flash(:info, gettext("Appel enregistré"))}

      {:error, reason} ->
        {:noreply, RollCall.put_error(socket, reason)}
    end
  end

  def handle_event("record", _params, socket), do: {:noreply, socket}

  defp no_lessons_title({:holiday, label}), do: gettext("Jour férié : %{label}", label: label)
  defp no_lessons_title(_), do: gettext("Pas de cours aujourd'hui")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-day" class="flex flex-col gap-5">
        <.page_header
          eyebrow={
            gettext("Ma journée · %{date} · %{time}",
              date: Dates.long(@today),
              time: Calendar.strftime(@now, "%H:%M")
            )
          }
          title={gettext("Appel")}
        >
          <:actions :if={@slots != []}>
            <.side_chip id="calls-done">
              {gettext("%{done} / %{total} appels faits",
                done: Enum.count(@slots, &(&1.status == :done)),
                total: length(@slots)
              )}
            </.side_chip>
          </:actions>
        </.page_header>

        <div :if={@slots == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={no_lessons_title(@day_off)} />
        </div>

        <div
          :if={@slots != []}
          class="grid items-start gap-5 [grid-template-columns:repeat(auto-fit,minmax(300px,1fr))]"
        >
          <div class="flex flex-col gap-5">
            <div id="today-slots" class="flex flex-col gap-1.5">
              <h2 class="ta-eyebrow">{gettext("Mes créneaux du jour")}</h2>
              <.slot_row
                :for={slot <- @slots}
                id={"slot-#{slot_key(slot)}"}
                slot={slot}
                selected={@selected == slot_key(slot)}
                patch={slot.status != :upcoming && ~p"/school/today?slot=#{slot_key(slot)}"}
              />
            </div>

            <div :if={@missed != []} id="missed-this-week" class="flex flex-col gap-1.5">
              <h2 class="ta-eyebrow">{gettext("Appels manquants cette semaine")}</h2>
              <.link
                :for={m <- @missed}
                id={"missed-#{m.class_group.id}-#{m.period.id}-#{m.date}"}
                navigate={
                  ~p"/school/classes/#{m.class_group.id}/attendance/#{m.period.id}?date=#{Date.to_iso8601(m.date)}"
                }
                class="grid grid-cols-[112px_minmax(0,1fr)_auto] items-center gap-3 rounded-box border border-base-300 bg-base-100 px-3.5 py-[11px] transition-colors hover:border-warning/70"
              >
                <span class="ta-num flex flex-col">
                  <span class="whitespace-nowrap text-[0.88rem] font-semibold">{Dates.short(m.date)}</span>
                  <span class="text-[0.7rem] text-base-content/75">
                    {m.period.label} · {hm(m.period.start_time)}
                  </span>
                </span>
                <span class="flex min-w-0 flex-col gap-0.5">
                  <span class="text-[0.95rem] font-semibold">{m.class_group.label}</span>
                  <span class="truncate text-[0.78rem] text-base-content/75">{m.subject}</span>
                </span>
                <.tag tone={:warning}>{gettext("Non fait")}</.tag>
              </.link>
            </div>
          </div>

          <RollCall.roll_panel :if={@roll} roll={@roll} title={roll_title(@roll)} />
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :slot, :map, required: true
  attr :selected, :boolean, required: true
  attr :patch, :any, required: true

  defp slot_row(assigns) do
    ~H"""
    <.link
      :if={@patch}
      id={@id}
      patch={@patch}
      aria-current={@selected && "true"}
      class={[slot_class(), selected_class(@selected)]}
    >
      <.slot_cells slot={@slot} />
    </.link>
    <div
      :if={!@patch}
      id={@id}
      class={[slot_class(), "cursor-default border-base-300 bg-base-100 opacity-60"]}
    >
      <.slot_cells slot={@slot} />
    </div>
    """
  end

  defp slot_class,
    do:
      "grid grid-cols-[64px_minmax(0,1fr)_auto] items-center gap-3 rounded-box border px-3.5 py-[11px] text-left transition-colors"

  defp selected_class(true), do: "border-primary bg-primary/12"
  defp selected_class(false), do: "border-base-300 bg-base-100 hover:border-primary/60"

  attr :slot, :map, required: true

  defp slot_cells(assigns) do
    ~H"""
    <span class="ta-num flex flex-col">
      <span class="truncate text-[0.88rem] font-semibold">{@slot.period.label}</span>
      <span class="text-[0.7rem] text-base-content/75">{hm(@slot.period.start_time)}</span>
    </span>
    <span class="flex min-w-0 flex-col gap-0.5">
      <span class="text-[0.95rem] font-semibold">{@slot.class_group.label}</span>
      <span class="truncate text-[0.78rem] text-base-content/75">{@slot.subject}</span>
    </span>
    <.status_tag status={@slot.status} absent={@slot.absent} />
    """
  end

  attr :status, :atom, required: true
  attr :absent, :integer, required: true

  defp status_tag(%{status: :done} = assigns),
    do: ~H|<.tag tone={:primary}>{gettext("Fait · %{count} abs.", count: @absent)}</.tag>|

  defp status_tag(%{status: :in_progress} = assigns),
    do: ~H|<.tag tone={:warning}>{gettext("En cours")}</.tag>|

  defp status_tag(%{status: :missed} = assigns),
    do: ~H|<.tag tone={:warning}>{gettext("Non fait")}</.tag>|

  defp status_tag(%{status: :upcoming} = assigns),
    do: ~H|<.tag tone={:muted}>{gettext("À venir")}</.tag>|

  attr :tone, :atom, required: true
  slot :inner_block, required: true

  defp tag(assigns) do
    ~H"""
    <span class={[
      "ta-num whitespace-nowrap rounded-full px-2 py-[3px] text-[0.68rem] font-semibold",
      tone_class(@tone)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp tone_class(:primary), do: "bg-primary/20 text-primary"
  defp tone_class(:warning), do: "bg-warning/25 text-warning"
  defp tone_class(:muted), do: "bg-base-content/10 text-base-content/75"

  defp roll_title(roll),
    do: "#{roll.period.label} · #{roll.cg.label} — #{hm(roll.period.start_time)}"

  defp hm(time), do: Calendar.strftime(time, "%H:%M")
end
