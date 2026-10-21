defmodule TeacherAssistantWeb.School.FeeControlLive do
  @moduledoc """
  « Contrôle des frais » of one class (Fees 2): the list the bursar reads in the
  classroom — who must leave (with what they owe), who may stay although late (and
  why), how many are up to date. She ticks « Sorti » for each student who actually left;
  the day's roll calls then show « Renvoyé pour frais ». `?date=` picks another day.
  The fees axis ticks; the class's form master reads.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, FeeControl, Fees}
  alias TeacherAssistant.Academics.{Reference, ReturnNoteReason}
  alias TeacherAssistantWeb.Money

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Fees.can_manage_fees?(scope) or Enrollment.class_manager?(scope, cg) do
      {:ok, assign(socket, cg: cg, can_edit?: Fees.can_manage_fees?(scope))}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    date =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, date} -> date
        _ -> Reference.today()
      end

    {:noreply, socket |> assign(date: date) |> load()}
  end

  def handle_event("toggle_sent_out", %{"id" => id}, socket) do
    with true <- socket.assigns.can_edit?,
         %{} = row <- Enum.find(socket.assigns.control.must_leave, &(&1.enrollment.id == id)) do
      if row.sent_out?,
        do: FeeControl.undo_send_out(scope(socket), row.enrollment, socket.assigns.date),
        else: FeeControl.record_send_out(scope(socket), row.enrollment, socket.assigns.date)

      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("tick_all", _params, socket) do
    if socket.assigns.can_edit? do
      for row <- socket.assigns.control.must_leave,
          not row.sent_out?,
          do: FeeControl.record_send_out(scope(socket), row.enrollment, socket.assigns.date)
    end

    {:noreply, load(socket)}
  end

  defp scope(socket), do: socket.assigns.current_scope

  defp load(socket),
    do:
      assign(socket,
        control: FeeControl.class_control(scope(socket), socket.assigns.cg, socket.assigns.date)
      )

  @doc false
  def date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  @doc "Why a late student may stay: « promesse jusqu'au 31/10/2025 », « exonération »…"
  def why(%{reason: :promise, valid_until: until}),
    do: gettext("promesse jusqu'au %{date}", date: date(until))

  def why(%{reason: reason, valid_until: until}),
    do:
      "#{String.downcase(ReturnNoteReason.label(reason))} · #{gettext("jusqu'au %{date}", date: date(until))}"

  @doc "« 1re tranche (40 %) échue le 15/10/2025 »."
  def tranche_line(nil), do: gettext("Aucune tranche échue")

  def tranche_line(t),
    do:
      gettext("%{label} (%{percent} %) échue le %{date}",
        label: t.label,
        percent: t.percent,
        date: date(t.due_date)
      )

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="fee-control" class="mx-auto max-w-2xl space-y-5">
        <header class="flex flex-wrap items-end justify-between gap-3">
          <div>
            <.link navigate={~p"/school/classes/#{@cg.id}/fees"} class="ta-eyebrow link">
              {gettext("Frais")}
            </.link>
            <h1 id="control-title" class="mt-1.5 text-2xl font-semibold leading-[1.1] sm:text-[2rem]">
              {gettext("Contrôle des frais — %{class}", class: @cg.label)}
            </h1>
            <p class="mt-2 text-[0.95rem] text-base-content/80">
              {date(@date)} · {tranche_line(@control.tranche)}
            </p>
          </div>
          <a
            id="print-control"
            href={~p"/school/classes/#{@cg.id}/fees/control/print?#{[date: Date.to_iso8601(@date)]}"}
            target="_blank"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer")}
          </a>
        </header>

        <section id="must-leave" class="space-y-2">
          <div class="flex items-center justify-between gap-2">
            <h2 class="text-lg font-semibold text-error">
              {gettext("Doivent sortir — %{count}", count: length(@control.must_leave))}
            </h2>
            <button
              :if={@can_edit? and @control.must_leave != []}
              id="tick-all"
              type="button"
              phx-click="tick_all"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Tout cocher")}
            </button>
          </div>
          <ul class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
            <li :for={row <- @control.must_leave} class="flex items-center gap-3 px-4 py-3">
              <button
                :if={@can_edit?}
                id={"sorti-#{row.enrollment.id}"}
                type="button"
                phx-click="toggle_sent_out"
                phx-value-id={row.enrollment.id}
                role="checkbox"
                aria-checked={to_string(row.sent_out?)}
                aria-label={gettext("Sorti : %{name}", name: row.student.full_name)}
                class={[
                  "btn btn-sm min-w-20",
                  if(row.sent_out?, do: "btn-error", else: "btn-outline")
                ]}
              >
                <.icon :if={row.sent_out?} name="hero-check" class="size-4" /> {gettext("Sorti")}
              </button>
              <span class="flex-1 font-semibold">{row.student.full_name}</span>
              <span class="ta-num whitespace-nowrap text-sm">
                {gettext("reste %{amount}", amount: Money.format_amount(row.owed))}
              </span>
            </li>
            <li :if={@control.must_leave == []} class="px-4 py-3 text-sm text-base-content/70">
              {gettext("Personne.")}
            </li>
          </ul>
        </section>

        <section id="allowed" class="space-y-2">
          <h2 class="text-lg font-semibold text-success">
            {gettext("Autorisés malgré un retard — %{count}", count: length(@control.allowed))}
          </h2>
          <ul class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100">
            <li :for={row <- @control.allowed} class="flex items-center gap-3 px-4 py-3">
              <span class="flex-1 font-semibold">{row.student.full_name}</span>
              <span class="text-sm text-base-content/80">{why(row.note)}</span>
            </li>
            <li :if={@control.allowed == []} class="px-4 py-3 text-sm text-base-content/70">
              {gettext("Personne.")}
            </li>
          </ul>
        </section>

        <p id="up-to-date" class="text-sm text-base-content/70">
          {ngettext(
            "L'autre élève est à jour.",
            "Les %{count} autres élèves sont à jour.",
            @control.up_to_date
          )}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
