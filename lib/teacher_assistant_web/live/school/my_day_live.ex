defmodule TeacherAssistantWeb.School.MyDayLive do
  @moduledoc """
  Enseignant → Ma journée (spec G, V01/V03): today's slots with their roll-call
  status beside the roll call of the selected slot (`?slot=<class>-<period>`),
  and this week's missed roll calls. The teaching space's home.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Assessment, Attendance, Curriculum, Organization}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.School.RollCall

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Curriculum.list_units_for_scope(scope) != [] do
      today = Reference.today()

      {:ok,
       socket
       |> assign(today: today, roll: nil, selected: nil, seq: current_sequence(scope, today))
       |> load_day()}
    else
      {:ok, push_navigate(socket, to: space_home(scope))}
    end
  end

  defp space_home(%{capabilities: %{space: %{home: home}}}) when home != "/school/today", do: home
  defp space_home(_scope), do: ~p"/school/classes"

  defp current_sequence(%{current_academic_year: nil}, _today), do: nil

  defp current_sequence(%{current_academic_year: year} = scope, today),
    do: scope |> Organization.list_sequences(year) |> Assessment.default_sequence(today)

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

  def handle_event("all_present", _params, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.all_present(&1)))}

  def handle_event("minutes", %{"minutes" => minutes}, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.set_minutes(&1, minutes)))}

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
          eyebrow={eyebrow(@today, @seq)}
          title={gettext("Ma journée")}
          subtitle={@slots != [] && subtitle(@slots)}
        />

        <div :if={@slots == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={no_lessons_title(@day_off)} />
        </div>

        <div :if={@slots != []} class="grid items-start gap-4 lg:grid-cols-3">
          <div class="flex flex-col gap-4">
            <div id="today-slots" class="ta-panel flex flex-col gap-1.5 !p-3">
              <h2 class="ta-eyebrow px-1 pb-1">{gettext("Mes créneaux du jour")}</h2>
              <.slot_row
                :for={slot <- @slots}
                id={"slot-#{slot_key(slot)}"}
                slot={slot}
                selected={@selected == slot_key(slot)}
                patch={slot.status != :upcoming && ~p"/school/today?slot=#{slot_key(slot)}"}
              />
            </div>

            <div :if={@missed != []} id="missed-this-week" class="ta-panel flex flex-col gap-1.5 !p-3">
              <div class="flex items-baseline justify-between px-1 pb-1">
                <h2 class="ta-eyebrow">{gettext("Appels manquants cette semaine")}</h2>
                <span class="ta-num rounded-full bg-error/20 px-2 text-[0.7rem] font-semibold text-error">
                  {length(@missed)}
                </span>
              </div>
              <div
                :for={m <- @missed}
                id={"missed-#{m.class_group.id}-#{m.period.id}-#{m.date}"}
                class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 rounded-box border border-base-300 px-3 py-2"
              >
                <span class="flex min-w-0 flex-col">
                  <span class="truncate text-[0.9rem] font-semibold">
                    {m.class_group.label} · {m.subject}
                  </span>
                  <span class="ta-num text-[0.72rem] text-base-content/70">
                    {Dates.short(m.date)} · {m.period.label} · {hm(m.period.start_time)}
                  </span>
                </span>
                <.link
                  navigate={
                    ~p"/school/classes/#{m.class_group.id}/attendance/#{m.period.id}?date=#{Date.to_iso8601(m.date)}"
                  }
                  class="btn btn-outline btn-xs"
                >
                  {gettext("Faire l'appel")}
                </.link>
              </div>
            </div>
          </div>

          <div class="lg:col-span-2">
            <div
              :if={!@roll}
              id="no-roll-now"
              class="ta-panel flex items-center gap-3 text-sm text-base-content/70"
            >
              <.icon name="hero-clock" class="size-5" />
              {gettext("Aucun appel à faire maintenant. Le prochain s'ouvrira au début du créneau.")}
            </div>
            <RollCall.roll_panel
              :if={@roll}
              roll={@roll}
              title={roll_title(@roll)}
              eyebrow={roll_eyebrow(@slots, @selected)}
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp eyebrow(today, nil), do: Dates.long(today)

  defp eyebrow(today, seq),
    do: Dates.long(today) <> " · " <> gettext("Séquence %{n}", n: seq.number)

  defp subtitle(slots) do
    to_call = Enum.count(slots, &(&1.status in [:in_progress, :missed]))
    lessons = ngettext("%{count} cours aujourd'hui", "%{count} cours aujourd'hui", length(slots))

    if to_call > 0,
      do:
        lessons <>
          " · " <>
          ngettext(
            "%{count} appel à faire maintenant",
            "%{count} appels à faire maintenant",
            to_call
          ),
      else: lessons
  end

  # « En cours · 10:00 – 10:55 » over the panel when its slot is in progress, else
  # « Cours 2 · 08:55 – 09:50 ».
  defp roll_eyebrow(slots, selected) do
    case Enum.find(slots, &(slot_key(&1) == selected)) do
      %{status: :in_progress, period: p} ->
        gettext("En cours · %{from} – %{to}", from: hm(p.start_time), to: hm(p.end_time))

      %{period: p} ->
        "#{p.label} · #{hm(p.start_time)} – #{hm(p.end_time)}"

      nil ->
        nil
    end
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
      "grid grid-cols-[52px_minmax(0,1fr)_auto] items-center gap-3 rounded-box border px-3 py-2.5 text-left transition-colors"

  defp selected_class(true), do: "border-primary bg-primary/12"
  defp selected_class(false), do: "border-base-300 bg-base-100 hover:border-primary/60"

  attr :slot, :map, required: true

  defp slot_cells(assigns) do
    ~H"""
    <span class="ta-num text-[0.88rem] font-semibold">{hm(@slot.period.start_time)}</span>
    <span class="flex min-w-0 flex-col gap-0.5">
      <span class="truncate text-[0.92rem] font-semibold">
        {@slot.class_group.label} · {@slot.subject}
      </span>
      <span class="ta-num truncate text-[0.72rem] text-base-content/70">
        <%= if @slot.status == :done do %>
          {ngettext("%{count} absent", "%{count} absents", @slot.absent)}
        <% else %>
          {@slot.period.label}
        <% end %>
      </span>
    </span>
    <.status_tag status={@slot.status} absent={@slot.absent} />
    """
  end

  attr :status, :atom, required: true
  attr :absent, :integer, required: true

  defp status_tag(%{status: :done} = assigns),
    do: ~H|<.tag tone={:primary}>{gettext("Fait")}</.tag>|

  defp status_tag(%{status: :in_progress} = assigns),
    do: ~H|<.tag tone={:now}>{gettext("Maintenant")}</.tag>|

  defp status_tag(%{status: :missed} = assigns),
    do: ~H|<.tag tone={:error}>{gettext("Non fait")}</.tag>|

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
  defp tone_class(:now), do: "bg-warning text-warning-content"
  defp tone_class(:error), do: "bg-error/20 text-error"
  defp tone_class(:muted), do: "bg-base-300 text-base-content/75"

  defp roll_title(roll),
    do:
      gettext("Appel · %{class} · %{what}",
        class: roll.cg.label,
        what: (roll.teaching_context && roll.teaching_context.subject) || roll.period.label
      )

  defp hm(time), do: Calendar.strftime(time, "%H:%M")
end
