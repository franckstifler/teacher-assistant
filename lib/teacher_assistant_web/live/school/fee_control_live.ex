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
  import TeacherAssistantWeb.School.ClassShell, only: [class_shell: 1]

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- Fees.can_manage_fees?(scope) or Enrollment.class_manager?(scope, cg) do
      {:ok,
       socket
       |> assign(cg: cg, can_edit?: Fees.can_manage_fees?(scope))
       |> TeacherAssistantWeb.School.ClassShell.assign_shell()}
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

    # A send-out is set or undone on the day itself; other days are read-only.
    editable? = socket.assigns.can_edit? and date == Reference.today()
    {:noreply, socket |> assign(date: date, editable?: editable?) |> load()}
  end

  def handle_event("toggle_sent_out", %{"id" => id}, socket) do
    with true <- socket.assigns.editable?,
         %{} = row <- Enum.find(socket.assigns.control.must_leave, &(&1.enrollment.id == id)) do
      result =
        if row.sent_out?,
          do: FeeControl.undo_send_out(scope(socket), row.enrollment, socket.assigns.date),
          else: FeeControl.record_send_out(scope(socket), row.enrollment, socket.assigns.date)

      {:noreply, socket |> report([result]) |> load()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("tick_all", _params, socket) do
    if socket.assigns.editable? do
      results =
        for row <- socket.assigns.control.must_leave,
            not row.sent_out?,
            do: FeeControl.record_send_out(scope(socket), row.enrollment, socket.assigns.date)

      {:noreply, socket |> report(results) |> load()}
    else
      {:noreply, socket}
    end
  end

  # A refused send-out (closed year, rights) must not look like it worked.
  defp report(socket, results) do
    if Enum.any?(results, &match?({:error, _}, &1)),
      do: put_flash(socket, :error, gettext("Modification non enregistrée.")),
      else: socket
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
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["fees", "classes"]}
    >
      <.class_shell cg={@cg} shell={@shell} tab={:fees} trail={[gettext("Contrôle des frais")]}>
        <:actions>
          <a
            id="print-control"
            href={~p"/school/classes/#{@cg.id}/fees/control/print?#{[date: Date.to_iso8601(@date)]}"}
            target="_blank"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-printer" class="size-4" /> {gettext("Imprimer")}
          </a>
        </:actions>

        <section id="fee-control" class="mx-auto max-w-2xl space-y-5">
          <header>
            <h2 id="control-title" class="text-xl font-semibold leading-tight">
              {gettext("Contrôle des frais")}
            </h2>
            <p class="mt-1 text-[0.95rem] text-base-content/80">
              {date(@date)} · {tranche_line(@control.tranche)}
            </p>
          </header>

          <section id="must-leave" class="space-y-2">
            <div class="flex items-center justify-between gap-2">
              <h2 class="text-lg font-semibold text-error">
                {gettext("Doivent sortir — %{count}", count: length(@control.must_leave))}
              </h2>
              <button
                :if={@editable? and @control.must_leave != []}
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
                  :if={@editable?}
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
                <span
                  :if={!@editable? and row.sent_out?}
                  class="badge badge-error badge-sm"
                >
                  {gettext("Sorti")}
                </span>
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
      </.class_shell>
    </Layouts.app>
    """
  end
end
