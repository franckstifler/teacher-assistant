defmodule TeacherAssistantWeb.School.ClassOverviewLive do
  @moduledoc """
  The class's « Vue d'ensemble » tab, its root URL (UX refonte batch 5): « À régler
  pour cette classe » (the form master to designate inline, subjects without a
  teacher, students without a parent contact), then four glance tiles — the
  séquence's marks, today's roll calls, the séquence's absences and the weekly
  timetable hours. Each block shows only to a viewer who may open the matching tab;
  « Imprimer… » gathers the class's printouts.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Discipline, Enrollment, Organization}
  alias TeacherAssistant.{ReportCards, Scope, Timetabling}
  alias TeacherAssistant.Academics.{EntryProgress, Reference}
  alias TeacherAssistantWeb.{Dates, Spaces}
  alias TeacherAssistantWeb.School.ClassShell
  import ClassShell, only: [class_shell: 1]

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :overview) || {:elsewhere, cg} do
      {:ok,
       socket
       |> assign(
         page_title: ClassShell.page_title(cg, :overview),
         cg: cg,
         can_set_pp?: Enrollment.can_manage_classes?(scope)
       )
       |> load()}
    else
      # A viewer who may open another tab of the class lands there (spec 2026-10-08 §3).
      {:elsewhere, cg} ->
        case ClassShell.load(scope, cg).tabs do
          [{_tab, path} | _] -> {:ok, push_navigate(socket, to: path)}
          [] -> {:ok, push_navigate(socket, to: ~p"/school")}
        end

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def handle_event("set_pp", %{"user_id" => uid}, socket) when socket.assigns.can_set_pp? do
    with %{} = member <- Enum.find(socket.assigns.pp_candidates, &(&1.user_id == uid)),
         {:ok, cg} <-
           Enrollment.set_form_master(socket.assigns.current_scope, socket.assigns.cg, uid) do
      {:noreply,
       socket
       |> assign(cg: cg)
       |> load()
       |> put_flash(
         :info,
         gettext("%{name} est professeur principal de la classe.",
           name: Accounts.User.display_name(member.user)
         )
       )}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, Authz.put_failure(socket, error)}
    end
  end

  def handle_event("set_pp", _params, socket), do: {:noreply, socket}

  # --- Data -----------------------------------------------------------------------

  defp load(socket) do
    %{current_scope: scope, cg: cg} = socket.assigns
    roster = Enrollment.list_roster(scope, cg)
    socket = ClassShell.assign_shell(socket, roster: roster)
    tabs = Enum.map(socket.assigns.shell.tabs, &elem(&1, 0))
    today = Reference.today()
    year = scope.current_academic_year
    current? = year != nil and year.id == cg.academic_year_id

    sequence =
      if current?,
        do: EntryProgress.default_sequence(Organization.list_sequences(scope, year), today)

    ctx = %{scope: scope, cg: cg, tabs: tabs, today: today, year: year, sequence: sequence}

    assign(socket,
      tabs: tabs,
      roster_count: length(roster),
      no_contact: no_contact(scope, roster, tabs),
      pp_candidates: pp_candidates(scope, cg, socket.assigns.can_set_pp?),
      tiles:
        Enum.reject(
          [notes_tile(ctx), calls_tile(ctx), absences_tile(ctx), timetable_tile(ctx)],
          &is_nil/1
        )
    )
  end

  # Students without a main contact (nil when the viewer cannot open the roster).
  defp no_contact(scope, roster, tabs) do
    if :students in tabs do
      contacts = Enrollment.primary_guardians(scope, Enum.map(roster, & &1.student.id))
      Enum.count(roster, &(not Map.has_key?(contacts, &1.student.id)))
    end
  end

  # The members the form master is picked from: the class's teachers, else everyone.
  defp pp_candidates(_scope, %{form_master_user_id: uid}, _can?) when not is_nil(uid), do: []
  defp pp_candidates(_scope, _cg, false), do: []

  defp pp_candidates(scope, cg, true) do
    members = Accounts.list_members(scope)

    teachers =
      scope
      |> Curriculum.list_assignments_for_class(cg)
      |> MapSet.new(& &1.teacher_user_id)

    candidates = Enum.filter(members, &MapSet.member?(teachers, &1.user_id))

    if(candidates == [], do: members, else: candidates)
    |> Enum.sort_by(&String.downcase(Accounts.User.display_name(&1.user)))
  end

  defp module?(scope, key), do: Scope.module?(scope, key)

  defp notes_tile(%{sequence: nil}), do: nil

  defp notes_tile(%{scope: scope, cg: cg, tabs: tabs, year: year, sequence: seq, today: today}) do
    if :results in tabs and module?(scope, :notes) do
      {started, total} = EntryProgress.class_subjects_started(scope, year, cg, seq)
      rate = EntryProgress.class_rate(scope, year, cg, [seq])

      %{
        id: "tile-notes",
        label: gettext("Notes Séq. %{n}", n: seq.number),
        value: "#{started} / #{total}",
        sub:
          join([
            gettext("matières commencées"),
            rate && gettext("%{rate} % saisi", rate: rate),
            Dates.countdown(seq.grade_entry_deadline, today)
          ]),
        tone: if(total > 0 and started == total, do: :ok, else: :neutral),
        path: ClassShell.tab_url(cg, :results)
      }
    end
  end

  defp calls_tile(%{scope: scope, cg: cg, tabs: tabs, today: today, year: year}) do
    cond do
      :register not in tabs or not module?(scope, :appel) or year == nil ->
        nil

      cg.paper_roll_call ->
        %{
          id: "tile-calls",
          label: gettext("Appels aujourd'hui"),
          value: gettext("Sur feuille"),
          sub: gettext("saisis par le surveillant"),
          tone: :neutral,
          path: ClassShell.tab_url(cg, :register)
        }

      true ->
        lessons = Attendance.class_lessons(scope, cg, today, today, Reference.now())
        done = Enum.count(lessons, &(&1.status == :done))
        missed = Enum.count(lessons, &(&1.status == :missed))

        %{
          id: "tile-calls",
          label: gettext("Appels aujourd'hui"),
          value: if(lessons == [], do: "—", else: "#{done} / #{length(lessons)}"),
          sub:
            cond do
              lessons == [] -> gettext("pas de cours aujourd'hui")
              missed > 0 -> ngettext("%{count} appel manqué", "%{count} appels manqués", missed)
              true -> gettext("faits dans l'application")
            end,
          tone: if(missed > 0, do: :warn, else: :neutral),
          path: ClassShell.tab_url(cg, :register)
        }
    end
  end

  defp absences_tile(%{sequence: nil}), do: nil

  defp absences_tile(%{scope: scope, cg: cg, tabs: tabs, today: today, sequence: seq}) do
    with true <- :register in tabs and module?(scope, :appel),
         {first, last} <- Attendance.current_sequence_range(scope, today) do
      rows =
        scope
        |> Attendance.absence_days(first, last, today)
        |> Enum.filter(&(&1.class_group.id == cg.id))

      over = rows |> Enum.filter(& &1.flagged?) |> Enum.uniq_by(& &1.enrollment.id) |> length()
      alert = Attendance.school_life_rules(scope).absence_alert_hours

      %{
        id: "tile-absences",
        label: gettext("Absences Séq. %{n}", n: seq.number),
        value: hours(Enum.sum_by(rows, & &1.minutes)),
        sub:
          if(over == 0,
            do: gettext("aucun élève au-delà de %{hours} h", hours: alert),
            else:
              ngettext(
                "%{count} élève au-delà de %{hours} h",
                "%{count} élèves au-delà de %{hours} h",
                over,
                hours: alert
              )
          ),
        tone: if(over > 0, do: :error, else: :neutral),
        path:
          if(Discipline.can_manage_conduct?(scope),
            do: ~p"/school/absences?class=#{cg.id}",
            else: ClassShell.tab_url(cg, :register)
          )
      }
    else
      _ -> nil
    end
  end

  defp timetable_tile(%{scope: scope, cg: cg, tabs: tabs}) do
    if :timetable in tabs and module?(scope, :emploi_du_temps) do
      %{slots: slots, tally: tally} = Timetabling.class_timetable(scope, cg)
      to_place = Enum.sum_by(tally, &max((&1.required || 0) - &1.placed, 0))

      %{
        id: "tile-timetable",
        label: gettext("Emploi du temps"),
        value: gettext("%{count} h", count: map_size(slots)),
        sub:
          if(to_place > 0,
            do: ngettext("%{count} h à placer", "%{count} h à placer", to_place),
            else: gettext("par semaine")
          ),
        tone: if(to_place > 0, do: :warn, else: :neutral),
        path: ClassShell.tab_url(cg, :timetable)
      }
    end
  end

  defp join(parts), do: parts |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")

  # « 0 h », « 3 h », « 3 h 20 »
  defp hours(minutes) do
    case {div(minutes, 60), rem(minutes, 60)} do
      {h, 0} -> "#{h} h"
      {h, m} -> "#{h} h #{String.pad_leading(to_string(m), 2, "0")}"
    end
  end

  defp todo_count(assigns) do
    Enum.count(
      [
        assigns.pp_candidates != [],
        :teachings in assigns.tabs and assigns.shell.unassigned > 0,
        (assigns.no_contact || 0) > 0
      ],
      & &1
    )
  end

  defp contacts_path(scope, cg) do
    if Enrollment.can_manage_register?(scope),
      do: ~p"/school/students?class=#{cg.id}&no_contact=1",
      else: ClassShell.tab_url(cg, :students)
  end

  defp print?(scope, path), do: Spaces.path_allowed?(scope, path)

  # --- View -----------------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :todo, todo_count(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:overview}>
        <:actions>
          <.action_menu
            id="class-print-menu"
            text={gettext("Imprimer…")}
            icon="hero-printer"
            label={gettext("Imprimer")}
          >
            <:item
              id="print-class-list"
              icon="hero-document-text"
              href={~p"/school/classes/#{@cg.id}/class-list/print"}
              target="_blank"
            >
              {gettext("Liste officielle")}
            </:item>
            <:item
              id="print-working-list"
              icon="hero-table-cells"
              href={~p"/school/classes/#{@cg.id}/class-list/working/print"}
              target="_blank"
            >
              {gettext("Liste de travail")}
            </:item>
            <:item
              :if={
                :timetable in @tabs and
                  print?(@current_scope, ~p"/school/classes/#{@cg.id}/timetable/print")
              }
              id="print-timetable"
              icon="hero-calendar-days"
              href={~p"/school/classes/#{@cg.id}/timetable/print"}
              target="_blank"
            >
              {gettext("Emploi du temps")}
            </:item>
            <:item
              :if={
                :register in @tabs and @cg.paper_roll_call and
                  print?(@current_scope, ~p"/school/classes/#{@cg.id}/roll-sheet/print")
              }
              id="print-roll-sheet"
              icon="hero-clipboard-document-list"
              href={~p"/school/classes/#{@cg.id}/roll-sheet/print"}
              target="_blank"
            >
              {gettext("Feuille d'appel de la semaine")}
            </:item>
            <:item
              :if={
                Enrollment.can_manage_register?(@current_scope) and
                  print?(@current_scope, ~p"/school/classes/#{@cg.id}/cards/print")
              }
              id="print-cards"
              icon="hero-identification"
              href={~p"/school/classes/#{@cg.id}/cards/print"}
              target="_blank"
            >
              {gettext("Cartes scolaires")}
            </:item>
            <:item
              :if={
                ReportCards.can_publish?(@current_scope) and
                  print?(@current_scope, ~p"/school/classes/#{@cg.id}/mark-sheet/print")
              }
              id="print-mark-sheet"
              icon="hero-table-cells"
              href={~p"/school/classes/#{@cg.id}/mark-sheet/print"}
              target="_blank"
            >
              {gettext("Relevé des notes")}
            </:item>
          </.action_menu>
        </:actions>

        <.attention_card
          id="class-todo"
          count={@todo}
          title={gettext("À régler pour cette classe")}
        >
          <li
            :if={@pp_candidates != []}
            id="todo-form-master"
            class="ta-row-rule flex flex-wrap items-center gap-x-3 gap-y-2 py-2.5 last:border-b-0"
          >
            <span class="flex min-w-0 flex-[1_1_16rem] flex-col">
              <span class="text-[0.95rem] font-semibold leading-snug">
                {gettext("Professeur principal")}
              </span>
              <span class="text-[0.8rem] text-base-content/70">
                {gettext("Prépare le conseil de classe · requis pour les bulletins")}
              </span>
            </span>
            <form id="pp-form" phx-change="set_pp" class="w-full sm:w-64">
              <select
                id="pp-select"
                name="user_id"
                aria-label={gettext("Professeur principal")}
                class="select select-sm w-full border-dashed"
              >
                <option value="">{gettext("Choisir un enseignant de la classe…")}</option>
                <option :for={m <- @pp_candidates} value={m.user_id}>
                  {Accounts.User.display_name(m.user)}
                </option>
              </select>
            </form>
          </li>
          <.attention_row
            :if={:teachings in @tabs and @shell.unassigned > 0}
            id="todo-unassigned"
            title={
              ngettext(
                "1 matière sans enseignant",
                "%{count} matières sans enseignant",
                @shell.unassigned
              )
            }
            reason={Enum.map_join(@shell.unassigned_subjects, " · ", & &1.name)}
            action={gettext("Affecter")}
            navigate={ClassShell.tab_url(@cg, :teachings)}
          />
          <.attention_row
            :if={(@no_contact || 0) > 0}
            id="todo-contacts"
            title={
              if @no_contact == @roster_count,
                do: gettext("Aucun contact parent"),
                else:
                  ngettext(
                    "1 élève sans contact parent",
                    "%{count} élèves sans contact parent",
                    @no_contact
                  )
            }
            reason={
              gettext("%{with} sur %{total} · utile pour les avis d'absence et de frais",
                with: @roster_count - @no_contact,
                total: @roster_count
              )
            }
            action={gettext("Voir les élèves")}
            navigate={contacts_path(@current_scope, @cg)}
          />
        </.attention_card>

        <section
          :if={@tiles != []}
          id="class-glance"
          aria-label={gettext("En un coup d'œil")}
          class="grid grid-cols-2 gap-3 lg:grid-cols-4"
        >
          <.stat_tile
            :for={t <- @tiles}
            id={t.id}
            label={t.label}
            value={t.value}
            sub={t.sub}
            tone={t.tone}
            navigate={t.path}
          />
        </section>

        <p
          :if={@todo == 0 and @tiles == []}
          class="ta-section px-4 py-6 text-center text-sm text-base-content/70"
        >
          {gettext("Rien à régler pour cette classe.")}
        </p>
      </.class_shell>
    </Layouts.app>
    """
  end
end
