defmodule TeacherAssistantWeb.School.MyDayLive do
  @moduledoc """
  Enseignant → Ma journée (spec G, V01/V03; UI review 2026-10-14). Phone first:

    * a « Maintenant » card for the lesson in progress (else the next one, else the
      last missed one) with « Faire l'appel » and « Saisir des notes »;
    * the roll call of the selected slot (`?slot=<class>-<period>`) in its place
      once opened, names in full and a sticky « Valider l'appel »;
    * today's lessons as a timeline, breaks as thin separators — a lesson whose
      roll call can be taken opens it;
    * this week's missed roll calls, folded to a count line.

  The teaching space's home.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Assessment, Attendance, Curriculum, Organization}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.School.RollCall

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil and Curriculum.list_units_for_scope(scope) != [] do
      today = Reference.today()

      {:ok,
       socket
       |> assign(
         today: today,
         roll: nil,
         selected: nil,
         seq: current_sequence(scope, today),
         breaks: scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :break))
       )
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

  # The roll call opens only on demand (« Faire l'appel », a tap on a lesson):
  # `?slot=` names a slot whose roll call can be taken (not upcoming).
  def handle_params(params, _uri, socket) do
    %{slots: slots, current_scope: scope, today: today} = socket.assigns

    case Enum.find(slots, &(&1.status != :upcoming and slot_key(&1) == params["slot"])) do
      nil ->
        {:noreply, assign(socket, selected: nil, roll: nil)}

      slot ->
        roll =
          case RollCall.open(scope, slot.class_group.id, slot.period.id, today) do
            {:ok, roll} -> roll
            {:error, _} -> nil
          end

        {:noreply, assign(socket, selected: roll && slot_key(slot), roll: roll)}
    end
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
    assigns =
      assign(assigns,
        focus: focus_slot(assigns.slots, NaiveDateTime.to_time(assigns.now)),
        selected_slot: Enum.find(assigns.slots, &(slot_key(&1) == assigns.selected))
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="my-day" class="flex flex-col gap-5">
        <.page_header
          eyebrow={eyebrow(@today, @seq)}
          title={greeting(@current_scope.current_user)}
          subtitle={@slots != [] && subtitle(@slots)}
        />

        <div :if={@slots == []} id="no-lessons">
          <.empty_state icon="hero-sun" title={no_lessons_title(@day_off)} />
        </div>

        <div
          :if={@slots != []}
          class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_22rem]"
        >
          <div class="flex min-w-0 flex-col gap-4">
            <RollCall.roll_panel
              :if={@roll}
              roll={@roll}
              title={roll_title(@roll)}
              eyebrow={roll_eyebrow(@selected_slot)}
            >
              <:actions>
                <.link
                  :if={@selected_slot && @selected_slot.teaching_context_id}
                  id="roll-marks"
                  navigate={~p"/teacher/contexts/#{@selected_slot.teaching_context_id}/marks"}
                  class="btn btn-ghost btn-sm btn-square"
                  aria-label={gettext("Saisir des notes")}
                  title={gettext("Saisir des notes")}
                >
                  <.icon name="hero-pencil-square" class="size-5" />
                </.link>
                <.link
                  id="close-roll"
                  patch={~p"/school/today"}
                  class="btn btn-ghost btn-sm btn-square"
                  aria-label={gettext("Fermer l'appel")}
                  title={gettext("Fermer l'appel")}
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </.link>
              </:actions>
            </RollCall.roll_panel>

            <.now_card :if={!@roll && @focus} slot={@focus} />

            <div
              :if={!@roll && !@focus}
              id="now-card"
              class="ta-panel flex items-center gap-3 text-[0.95rem]"
            >
              <span class="grid size-10 shrink-0 place-items-center rounded-full bg-success/15 text-success">
                <.icon name="hero-check" class="size-5" />
              </span>
              <span>
                <span class="block font-semibold">{gettext("Journée terminée")}</span>
                <span class="text-sm text-base-content/70">
                  {gettext("Tous vos appels du jour sont faits.")}
                </span>
              </span>
            </div>
          </div>

          <div class="flex min-w-0 flex-col gap-4">
            <section id="today-slots" class="ta-section">
              <h2 class="px-4 pb-1 pt-4 text-base font-semibold">{gettext("Ma journée")}</h2>
              <ol class="flex flex-col pb-2">
                <.timeline_item
                  :for={item <- timeline(@slots, @breaks)}
                  item={item}
                  selected={@selected}
                />
              </ol>
            </section>

            <details
              :if={@missed != []}
              id="missed-this-week"
              class="ta-section group"
            >
              <summary class="flex min-h-14 cursor-pointer list-none items-center gap-3 px-4 py-3 [&::-webkit-details-marker]:hidden">
                <span class="ta-num grid size-7 shrink-0 place-items-center rounded-full bg-error/15 text-[0.8rem] font-semibold text-error">
                  {length(@missed)}
                </span>
                <span class="min-w-0 flex-1 text-[0.95rem] font-medium">
                  {ngettext(
                    "Appel manquant cette semaine",
                    "Appels manquants cette semaine",
                    length(@missed)
                  )}
                </span>
                <.icon
                  name="hero-chevron-down"
                  class="size-4 shrink-0 text-base-content/55 transition-transform group-open:rotate-180"
                />
              </summary>
              <ul class="border-t border-base-300">
                <li :for={m <- @missed}>
                  <.link
                    id={"missed-#{m.class_group.id}-#{m.period.id}-#{m.date}"}
                    navigate={
                      ~p"/school/classes/#{m.class_group.id}/attendance/#{m.period.id}?date=#{Date.to_iso8601(m.date)}"
                    }
                    class="ta-list-row"
                  >
                    <span class="flex min-w-0 flex-1 flex-col">
                      <span class="text-[0.92rem] font-medium leading-snug">
                        {m.class_group.label} · {m.subject}
                      </span>
                      <span class="ta-num text-[0.75rem] text-base-content/65">
                        {Dates.short(m.date)} · {m.period.label} · {hm(m.period.start_time)}
                      </span>
                    </span>
                    <span class="shrink-0 text-sm font-semibold text-primary">
                      {gettext("Faire l'appel")}
                    </span>
                    <.icon name="hero-chevron-right" class="size-4 shrink-0 text-base-content/45" />
                  </.link>
                </li>
              </ul>
            </details>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # The hero's lesson: the one under way (its roll call taken or not), else the
  # next one, else the last one missed today.
  defp focus_slot(slots, time) do
    Enum.find(slots, &under_way?(&1.period, time)) ||
      Enum.find(slots, &(&1.status == :upcoming)) ||
      slots |> Enum.filter(&(&1.status == :missed)) |> List.last()
  end

  defp under_way?(period, time),
    do:
      Time.compare(period.start_time, time) != :gt and Time.compare(time, period.end_time) == :lt

  attr :item, :any, required: true
  attr :selected, :string, default: nil

  defp timeline_item(%{item: {:break, period}} = assigns) do
    assigns = assign(assigns, :period, period)

    ~H"""
    <li class="flex items-center gap-2 px-4 py-1.5" aria-hidden="true">
      <span class="h-px flex-1 bg-base-300"></span>
      <span class="ta-num text-[0.7rem] text-base-content/55">
        {@period.label} · {hm(@period.start_time)}
      </span>
      <span class="h-px flex-1 bg-base-300"></span>
    </li>
    """
  end

  defp timeline_item(%{item: {:slot, slot}} = assigns) do
    assigns = assign(assigns, slot: slot, key: slot_key(slot))

    ~H"""
    <li>
      <.slot_row id={"slot-#{@key}"} slot={@slot} selected={@selected == @key} />
    </li>
    """
  end

  # Lessons and the breaks that fall between the first and the last one, by start time.
  defp timeline([], _breaks), do: []

  defp timeline(slots, breaks) do
    first = hd(slots).period.start_time
    last = List.last(slots).period.start_time

    breaks =
      for b <- breaks,
          Time.compare(b.start_time, first) == :gt,
          Time.compare(b.start_time, last) == :lt,
          do: {:break, b}

    (Enum.map(slots, &{:slot, &1}) ++ breaks)
    |> Enum.sort_by(fn {_kind, x} -> start_time(x) end, Time)
  end

  defp start_time(%{period: p}), do: p.start_time
  defp start_time(%{start_time: t}), do: t

  attr :slot, :map, required: true

  defp now_card(assigns) do
    ~H"""
    <div
      id="now-card"
      class={[
        "ta-panel flex flex-col gap-3 border-l-4 !p-4 sm:!p-5",
        hero_border(@slot.status)
      ]}
    >
      <div class="flex items-center justify-between gap-3">
        <p class={["ta-eyebrow", hero_tone(@slot.status)]}>{hero_eyebrow(@slot.status)}</p>
        <span class="ta-num text-[0.85rem] text-base-content/70">
          {hm(@slot.period.start_time)} – {hm(@slot.period.end_time)}
        </span>
      </div>
      <div>
        <h2 class="font-display text-[1.4rem] font-semibold leading-tight">
          {@slot.class_group.label} · {@slot.subject}
        </h2>
        <p id="now-state" class={["mt-1 text-[0.9rem]", state_tone(@slot.status)]}>
          {hero_state(@slot)}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <.link
          :if={@slot.status != :upcoming}
          id="now-call"
          patch={~p"/school/today?slot=#{slot_key(@slot)}"}
          class={[
            "btn h-11 max-sm:flex-1",
            if(@slot.status == :done, do: "btn-outline", else: "btn-primary")
          ]}
        >
          <.icon name="hero-clipboard-document-check" class="size-5" />
          {if @slot.status == :done, do: gettext("Modifier l'appel"), else: gettext("Faire l'appel")}
        </.link>
        <.link
          :if={@slot.teaching_context_id}
          id="now-marks"
          navigate={~p"/teacher/contexts/#{@slot.teaching_context_id}/marks"}
          class="btn btn-ghost h-11 max-sm:flex-1"
        >
          <.icon name="hero-pencil-square" class="size-5" /> {gettext("Saisir des notes")}
        </.link>
      </div>
    </div>
    """
  end

  defp hero_eyebrow(:in_progress), do: gettext("Maintenant")
  defp hero_eyebrow(:upcoming), do: gettext("Prochain cours")
  defp hero_eyebrow(:missed), do: gettext("Appel non fait")
  defp hero_eyebrow(:done), do: gettext("Maintenant")

  defp hero_state(%{status: :done, absent: n}),
    do:
      gettext("Appel fait") <>
        " · " <> ngettext("%{count} absent", "%{count} absents", n)

  defp hero_state(%{status: :in_progress}), do: gettext("Appel à faire")
  defp hero_state(%{status: :missed}), do: gettext("Créneau terminé, appel non fait")

  defp hero_state(%{status: :upcoming, period: p}),
    do: gettext("L'appel s'ouvrira à %{time}", time: hm(p.start_time))

  defp hero_border(:in_progress), do: "border-l-warning"
  defp hero_border(:missed), do: "border-l-error"
  defp hero_border(:done), do: "border-l-success"
  defp hero_border(:upcoming), do: "border-l-base-300"

  defp hero_tone(:in_progress), do: "text-warning"
  defp hero_tone(:missed), do: "text-error"
  defp hero_tone(_), do: nil

  defp state_tone(:done), do: "text-success"
  defp state_tone(:in_progress), do: "text-warning"
  defp state_tone(:missed), do: "text-error"
  defp state_tone(:upcoming), do: "text-base-content/70"

  defp greeting(%User{} = user) do
    case User.display_name(user) do
      "" -> gettext("Ma journée")
      name -> gettext("Bonjour, %{name}", name: name)
    end
  end

  defp greeting(_user), do: gettext("Ma journée")

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
  defp roll_eyebrow(%{status: :in_progress, period: p}),
    do: gettext("En cours · %{from} – %{to}", from: hm(p.start_time), to: hm(p.end_time))

  defp roll_eyebrow(%{period: p}), do: "#{p.label} · #{hm(p.start_time)} – #{hm(p.end_time)}"
  defp roll_eyebrow(nil), do: nil

  attr :id, :string, required: true
  attr :slot, :map, required: true
  attr :selected, :boolean, required: true

  # A lesson of the timeline: a link opening its roll call once it has started.
  defp slot_row(assigns) do
    ~H"""
    <.link
      :if={@slot.status != :upcoming}
      id={@id}
      patch={~p"/school/today?slot=#{slot_key(@slot)}"}
      aria-current={@selected && "true"}
      class={[row_class(), @selected && "bg-primary/12", !@selected && "hover:bg-base-content/5"]}
    >
      <.slot_cells slot={@slot} />
    </.link>
    <div :if={@slot.status == :upcoming} id={@id} class={row_class()}>
      <.slot_cells slot={@slot} />
    </div>
    """
  end

  defp row_class,
    do:
      "grid min-h-14 grid-cols-[3rem_0.75rem_minmax(0,1fr)_auto] items-center gap-x-2.5 px-4 py-2 transition-colors"

  attr :slot, :map, required: true

  defp slot_cells(assigns) do
    ~H"""
    <span class="ta-num flex flex-col text-[0.85rem] font-semibold leading-tight">
      {hm(@slot.period.start_time)}
      <span class="text-[0.7rem] font-normal text-base-content/55">
        {hm(@slot.period.end_time)}
      </span>
    </span>
    <span class={["size-2.5 justify-self-center rounded-full", dot_class(@slot.status)]}></span>
    <span class="flex min-w-0 flex-col">
      <span class={[
        "text-[0.92rem] font-medium leading-snug",
        @slot.status == :done && "text-base-content/75"
      ]}>
        {@slot.class_group.label} · {@slot.subject}
      </span>
      <span class="ta-num text-[0.72rem] text-base-content/65">
        <%= if @slot.status == :done do %>
          {ngettext("%{count} absent", "%{count} absents", @slot.absent)}
        <% else %>
          {@slot.period.label}
        <% end %>
      </span>
    </span>
    <.status_tag status={@slot.status} />
    """
  end

  defp dot_class(:done), do: "bg-success"
  defp dot_class(:in_progress), do: "bg-warning ring-4 ring-warning/25"
  defp dot_class(:missed), do: "bg-error"
  defp dot_class(:upcoming), do: "border border-base-content/35"

  attr :status, :atom, required: true

  defp status_tag(%{status: :done} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 whitespace-nowrap text-[0.75rem] font-semibold text-success">
      <.icon name="hero-check-mini" class="size-4" /> {gettext("Fait")}
    </span>
    """
  end

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
      "whitespace-nowrap rounded-full px-2 py-[3px] text-[0.7rem] font-semibold",
      tone_class(@tone)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp tone_class(:now), do: "bg-warning text-warning-content"
  defp tone_class(:error), do: "bg-error/15 text-error"
  defp tone_class(:muted), do: "text-base-content/60"

  defp roll_title(roll),
    do:
      gettext("Appel · %{class} · %{what}",
        class: roll.cg.label,
        what: (roll.teaching_context && roll.teaching_context.subject) || roll.period.label
      )

  defp hm(time), do: Calendar.strftime(time, "%H:%M")
end
