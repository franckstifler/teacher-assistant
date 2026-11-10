defmodule TeacherAssistantWeb.School.SequenceTrackingLive do
  @moduledoc """
  Censorat → Suivi de la saisie (spec F, N05; UX refonte 2026-11-03): per séquence,
  how far each teacher's mark entry has gone. Four figures on top, then one table
  grouped three ways — par enseignant (default, with checkboxes and « Relancer la
  sélection »), par classe (the classes × subjects grid and a course's detail) and
  par matière — filtered by a search.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Assessment, Organization, Pilotage, ReportCards}
  alias TeacherAssistant.Academics.{Lock, Reference}
  alias TeacherAssistantWeb.Dates

  @views ~w(teachers classes subjects)

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope.current_workspace == nil ->
        {:ok, push_navigate(socket, to: ~p"/school")}

      not Organization.can_manage_calendar?(scope) ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Le suivi des séquences est réservé à l'administration."))
         |> push_navigate(to: ~p"/school")}

      true ->
        year = scope.current_academic_year
        sequences = if year, do: Organization.list_sequences(scope, year), else: []

        {:ok,
         assign(socket,
           page_title: gettext("Suivi de la saisie des notes"),
           year: year,
           sequences: sequences,
           seq: nil,
           grid: nil,
           detail: nil,
           reminders: %{},
           competences: nil,
           teachers: [],
           view: "teachers",
           q: "",
           picked: MapSet.new()
         )}
    end
  end

  def handle_params(params, _uri, socket) do
    %{sequences: sequences, year: year, current_scope: scope} = socket.assigns
    view = if params["view"] in @views, do: params["view"], else: "teachers"
    socket = assign(socket, :view, view)

    case pick_sequence(sequences, params["seq"]) do
      nil ->
        {:noreply,
         assign(socket, seq: nil, grid: nil, detail: nil, reminders: %{}, competences: nil)}

      %{id: id} when socket.assigns.seq != nil and socket.assigns.seq.id == id ->
        # Same séquence, another grouping: keep the data and the selection.
        {:noreply, socket}

      seq ->
        grid = Assessment.sequence_entry_grid(scope, year, seq)
        reminders = Assessment.reminder_dates(scope, seq)
        competences = Pilotage.competences(scope, seq, grid)
        teachers = teacher_rows(grid, competences)

        {:noreply,
         assign(socket,
           seq: seq,
           grid: grid,
           detail: default_selection(grid),
           reminders: reminders,
           competences: competences,
           teachers: teachers,
           picked: default_picked(teachers, reminders)
         )}
    end
  end

  # An id that is not one of this year's séquences (another year, garbage) falls
  # back to the default one.
  defp pick_sequence(sequences, id) when is_binary(id) do
    Enum.find(sequences, &(&1.id == id)) || pick_sequence(sequences, nil)
  end

  defp pick_sequence(sequences, _id),
    do: Assessment.default_sequence(sequences, Reference.today())

  defp self_path(seq, view), do: ~p"/school/sequences?#{[seq: seq.id, view: view]}"

  def handle_event("pick-seq", %{"seq" => id}, socket),
    do:
      {:noreply,
       push_patch(socket, to: ~p"/school/sequences?#{[seq: id, view: socket.assigns.view]}")}

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, assign(socket, :q, String.trim(q))}

  def handle_event("select", %{"cg" => cg_id, "col" => col}, socket) do
    with {n, ""} <- Integer.parse(col),
         %{} = detail <- detail(socket.assigns.grid, cg_id, n) do
      {:noreply, assign(socket, :detail, detail)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick", %{"id" => id}, socket) do
    %{picked: picked, teachers: teachers, reminders: reminders} = socket.assigns

    # Never trust the client id: only a late teacher not yet reminded today is picked.
    picked =
      cond do
        MapSet.member?(picked, id) -> MapSet.delete(picked, id)
        Enum.any?(teachers, &(&1.id == id and pickable?(&1, reminders))) -> MapSet.put(picked, id)
        true -> picked
      end

    {:noreply, assign(socket, :picked, picked)}
  end

  def handle_event("pick-all", _params, socket) do
    %{picked: picked, teachers: teachers, reminders: reminders, q: q} = socket.assigns
    ids = for t <- filter_teachers(teachers, q), pickable?(t, reminders), do: t.id

    picked =
      if ids != [] and Enum.all?(ids, &MapSet.member?(picked, &1)),
        do: Enum.reduce(ids, picked, &MapSet.delete(&2, &1)),
        else: MapSet.union(picked, MapSet.new(ids))

    {:noreply, assign(socket, :picked, picked)}
  end

  def handle_event("clear-picked", _params, socket),
    do: {:noreply, assign(socket, :picked, MapSet.new())}

  def handle_event("remind-picked", _params, socket) do
    %{year: year, seq: seq, picked: picked, current_scope: scope} = socket.assigns
    {:ok, sent} = Assessment.remind_teachers(scope, year, seq, MapSet.to_list(picked))

    {:noreply,
     socket
     |> put_flash(:info, sent_message(sent))
     |> assign(reminders: Assessment.reminder_dates(scope, seq), picked: MapSet.new())}
  end

  def handle_event("remind", %{"tc" => tc_id}, socket) do
    %{grid: grid, seq: seq, current_scope: scope} = socket.assigns

    # Only a lagging course of the grid on screen can be reminded.
    case lagging_cell(grid, tc_id) do
      nil ->
        {:noreply, socket}

      cell ->
        case Assessment.remind_entry(scope, seq, tc_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               gettext("Relance envoyée à %{name}.", name: teacher_name(cell.teacher))
             )
             |> assign(:reminders, Assessment.reminder_dates(scope, seq))}

          {:error, :already_reminded} ->
            {:noreply, assign(socket, :reminders, Assessment.reminder_dates(scope, seq))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("La relance n'a pas pu être envoyée."))}
        end
    end
  end

  defp sent_message(0),
    do: gettext("Aucune nouvelle relance : chaque retard a déjà été relancé aujourd'hui.")

  defp sent_message(sent),
    do: ngettext("%{count} rappel envoyé.", "%{count} rappels envoyés.", sent)

  # --- Teachers and subjects ---------------------------------------------------------

  # One row per teacher having a course this year: their subjects, how many courses,
  # how many started (a mark entered), the competences still to write and their last
  # entry; `lagging` are the courses under 100 % (who « Relancer » reaches).
  defp teacher_rows(grid, competences) do
    labels = Map.new(grid.subjects, &{&1.key, &1.label})

    for row <- grid.rows,
        {key, %{teaching_context: %{teacher_user_id: id}} = cell} <- row.cells,
        not is_nil(id) do
      {id, labels[key], cell}
    end
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {id, [{_, _, first} | _] = entries} ->
      cells = Enum.map(entries, &elem(&1, 2))

      entries
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> summary(cells, competences)
      |> Map.merge(%{
        id: id,
        teacher: first.teacher,
        name: teacher_name(first.teacher),
        lagging:
          for(%{pct: pct} = c <- cells, is_integer(pct), pct < 100, do: c.teaching_context.id)
      })
    end)
    |> Enum.sort_by(&{&1.lagging == [], &1.started, String.downcase(&1.name)})
  end

  defp subject_rows(grid, competences) do
    for %{key: key, label: label} <- grid.subjects do
      cells = for row <- grid.rows, cell = row.cells[key], cell != nil, do: cell

      teachers =
        cells
        |> Enum.map(& &1.teacher)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)
        |> Enum.map(&teacher_name/1)
        |> Enum.sort()

      [label]
      |> summary(cells, competences)
      |> Map.merge(%{key: key, label: label, teachers: teachers})
    end
  end

  defp summary(subjects, cells, competences) do
    measurable = Enum.filter(cells, &is_integer(&1.pct))

    %{
      subjects: Enum.sort(subjects),
      courses: length(cells),
      measurable: length(measurable),
      started: Enum.count(measurable, &(&1.entered > 0)),
      complete: Enum.count(measurable, &(&1.pct == 100)),
      competences_left: Enum.count(cells, &Pilotage.competence_missing?(competences, &1)),
      last_entry_at:
        cells
        |> Enum.map(& &1.last_entry_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> nil end)
    }
  end

  defp reminded_today?(reminders, %{lagging: lagging}),
    do: lagging != [] and Enum.all?(lagging, &(reminders[&1] == Reference.today()))

  defp pickable?(teacher, reminders),
    do: teacher.lagging != [] and not reminded_today?(reminders, teacher)

  # As in the mockup, the teachers who have started nothing are ticked on arrival.
  defp default_picked(teachers, reminders) do
    for t <- teachers, t.started == 0, pickable?(t, reminders), into: MapSet.new(), do: t.id
  end

  defp matches?(_texts, ""), do: true

  defp matches?(texts, q) do
    q = String.downcase(q)
    Enum.any?(texts, &(&1 && String.contains?(String.downcase(&1), q)))
  end

  defp filter_teachers(teachers, q),
    do: Enum.filter(teachers, &matches?([&1.name | &1.subjects], q))

  defp filter_subjects(rows, q), do: Enum.filter(rows, &matches?([&1.label | &1.teachers], q))

  defp filter_classes(rows, subjects, q) do
    labels = Map.new(subjects, &{&1.key, &1.label})

    Enum.filter(rows, fn row ->
      texts =
        for {key, cell} <- row.cells, cell != nil, do: [labels[key], teacher_name(cell.teacher)]

      matches?([row.class_group.label | List.flatten(texts)], q)
    end)
  end

  # --- KPIs ------------------------------------------------------------------------

  defp kpis(grid, teachers, competences, reminders) do
    cells = for row <- grid.rows, cell <- Map.values(row.cells), cell != nil, do: cell
    today = Reference.today()

    %{
      assessments: Enum.sum_by(cells, &length(&1.assessments)),
      marks: Enum.sum_by(cells, & &1.entered),
      started: Enum.count(teachers, &(&1.started > 0)),
      late: grid.late_teacher_count,
      competence_gaps: competences && Pilotage.competence_gaps(grid, competences),
      reminded: map_size(reminders),
      reminded_today: Enum.count(reminders, fn {_tc, day} -> day == today end)
    }
  end

  # --- Per-class grid (the « Par classe » view) -------------------------------------

  defp seq_state(seq, today) do
    cond do
      Lock.locked?(seq, today) -> :closed
      Date.compare(seq.start_date, today) != :gt -> :current
      true -> :future
    end
  end

  defp seq_label(seq, :closed), do: gettext("Séq. %{n} · close", n: seq.number)
  defp seq_label(seq, :current), do: gettext("Séq. %{n} · en cours", n: seq.number)
  defp seq_label(seq, :future), do: gettext("Séq. %{n} · à venir", n: seq.number)

  defp lagging_cell(nil, _tc_id), do: nil

  defp lagging_cell(grid, tc_id) do
    grid.rows
    |> Enum.flat_map(&Map.values(&1.cells))
    |> Enum.find(fn
      %{pct: pct, teaching_context: %{id: ^tc_id}} when is_integer(pct) and pct < 100 -> true
      _ -> false
    end)
  end

  # A course is selected on arrival: the first one not complete, else the first.
  defp default_selection(grid) do
    cells =
      for row <- grid.rows,
          {subject, n} <- Enum.with_index(grid.subjects),
          match?(%{pct: pct} when is_integer(pct), row.cells[subject.key]),
          do: {row.class_group.id, n, row.cells[subject.key].pct}

    case Enum.find(cells, fn {_, _, pct} -> pct < 100 end) || List.first(cells) do
      {cg_id, n, _} -> detail(grid, cg_id, n)
      nil -> nil
    end
  end

  defp detail(grid, cg_id, n) do
    with %{} = subject <- Enum.at(grid.subjects, n),
         %{} = row <- Enum.find(grid.rows, &(&1.class_group.id == cg_id)),
         %{pct: pct} = cell when is_integer(pct) <- row.cells[subject.key] do
      %{cg_id: cg_id, col: n, class_group: row.class_group, subject: subject, cell: cell}
    else
      _ -> nil
    end
  end

  def render(assigns) do
    assigns =
      case assigns.grid do
        nil ->
          assign(assigns, kpis: nil, shown_teachers: [], subject_rows: [], class_rows: [])

        grid ->
          assign(assigns,
            kpis: kpis(grid, assigns.teachers, assigns.competences, assigns.reminders),
            shown_teachers: filter_teachers(assigns.teachers, assigns.q),
            subject_rows:
              if(assigns.view == "subjects",
                do: grid |> subject_rows(assigns.competences) |> filter_subjects(assigns.q),
                else: []
              ),
            class_rows: filter_classes(grid.rows, grid.subjects, assigns.q)
          )
      end

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="sequence-tracking" class="flex flex-col gap-5">
        <.page_header
          eyebrow={if @seq, do: eyebrow_text(@seq), else: gettext("Censorat")}
          title={gettext("Suivi de la saisie")}
        >
          <:actions :if={@grid}>
            <form id="seq-form" phx-change="pick-seq" class="w-full sm:w-auto">
              <label class="flex items-center gap-2 text-sm text-base-content/75">
                {gettext("Séquence")}
                <select id="seq-select" name="seq" class="select select-sm min-w-0 flex-1 sm:w-48">
                  <option
                    :for={s <- @sequences}
                    id={"seq-option-#{s.id}"}
                    value={s.id}
                    selected={s.id == @seq.id}
                  >
                    {seq_label(s, seq_state(s, Reference.today()))}
                  </option>
                </select>
              </label>
            </form>
            <.link
              :if={ReportCards.can_publish?(@current_scope)}
              id="print-mark-sheets"
              href={~p"/school/mark-sheets/print?#{[period: "seq:#{@seq.id}"]}"}
              target="_blank"
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-printer" class="size-4" />
              {gettext("Imprimer le relevé")}
            </.link>
          </:actions>
        </.page_header>

        <div
          :if={@grid == nil}
          id="no-sequences"
          class="ta-leaf flex items-start gap-3 text-sm text-base-content/80"
        >
          <.icon name="hero-calendar-days" class="size-5 shrink-0 text-base-content/70" />
          <p>
            {gettext(
              "Aucune séquence pour l'année en cours. Définissez le calendrier dans les paramètres pour suivre la saisie des notes."
            )}
          </p>
        </div>

        <%= if @grid do %>
          <div id="tracking-kpis" class="grid grid-cols-2 gap-2 sm:gap-3 lg:grid-cols-4">
            <.stat_tile
              id="kpi-assessments"
              label={gettext("Évaluations créées")}
              value={Integer.to_string(@kpis.assessments)}
              sub={ngettext("%{count} note saisie", "%{count} notes saisies", @kpis.marks)}
            />
            <.stat_tile
              id="kpi-started"
              label={gettext("Enseignants ayant commencé")}
              value={"#{@kpis.started} / #{length(@teachers)}"}
              tone={if @kpis.late == 0, do: :ok, else: :neutral}
              sub={ngettext("%{count} à relancer", "%{count} à relancer", @kpis.late)}
            />
            <.stat_tile
              id="kpi-competences"
              label={gettext("Cours sans compétence")}
              value={
                if @kpis.competence_gaps, do: Integer.to_string(@kpis.competence_gaps), else: "—"
              }
              tone={competence_tone(@kpis.competence_gaps)}
              sub={
                if @kpis.competence_gaps,
                  do: gettext("compétence APC de la séquence"),
                  else: gettext("bulletins sans APC")
              }
            />
            <.stat_tile
              id="kpi-reminders"
              label={gettext("Cours relancés")}
              value={Integer.to_string(@kpis.reminded)}
              sub={
                ngettext(
                  "dont %{count} aujourd'hui",
                  "dont %{count} aujourd'hui",
                  @kpis.reminded_today
                )
              }
            />
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <nav id="view-switch" class="ta-seg" aria-label={gettext("Regrouper par")}>
              <.link
                :for={{view, label} <- view_labels()}
                id={"view-#{view}"}
                patch={self_path(@seq, view)}
                class="ta-seg__btn"
                aria-current={view == @view && "true"}
              >
                {label}
              </.link>
            </nav>
            <form
              id="tracking-search"
              phx-change="search"
              phx-submit="search"
              class="min-w-0 flex-1 basis-56"
            >
              <label class="input input-sm w-full">
                <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                <input
                  type="search"
                  name="q"
                  value={@q}
                  phx-debounce="200"
                  placeholder={gettext("Enseignant, classe ou matière")}
                  aria-label={gettext("Rechercher")}
                  class="grow"
                />
              </label>
            </form>
          </div>

          <p :if={@grid.subjects == []} class="ta-panel text-sm text-base-content/70">
            {gettext("Aucun cours n'est encore attribué pour cette année.")}
          </p>

          <.teacher_table
            :if={@view == "teachers" and @grid.subjects != []}
            teachers={@shown_teachers}
            picked={@picked}
            reminders={@reminders}
            competences?={@competences != nil}
          />

          <.subject_table
            :if={@view == "subjects" and @grid.subjects != []}
            rows={@subject_rows}
            competences?={@competences != nil}
          />

          <div
            :if={@view == "classes" and @grid.subjects != []}
            class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_320px]"
          >
            <.class_grid
              grid={@grid}
              rows={@class_rows}
              competences={@competences}
              reminders={@reminders}
              detail={@detail}
            />
            <.cell_detail
              :if={@detail}
              detail={@detail}
              competences={@competences}
              reminders={@reminders}
            />
          </div>

          <.bulk_bar id="remind-bar" count={MapSet.size(@picked)} clear="clear-picked">
            <:actions>
              <button
                id="remind-picked"
                type="button"
                class="btn btn-warning btn-sm"
                phx-click="remind-picked"
                phx-disable-with={gettext("Envoi…")}
              >
                <.icon name="hero-bell-alert" class="size-4" />
                {gettext("Relancer la sélection · %{n}", n: MapSet.size(@picked))}
              </button>
            </:actions>
          </.bulk_bar>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp view_labels,
    do: [
      {"teachers", gettext("Par enseignant")},
      {"classes", gettext("Par classe")},
      {"subjects", gettext("Par matière")}
    ]

  defp competence_tone(nil), do: :none
  defp competence_tone(0), do: :ok
  defp competence_tone(_), do: :warn

  attr :teachers, :list, required: true
  attr :picked, :any, required: true
  attr :reminders, :map, required: true
  attr :competences?, :boolean, required: true

  defp teacher_table(assigns) do
    pickable = for t <- assigns.teachers, pickable?(t, assigns.reminders), do: t.id

    assigns =
      assign(assigns,
        pickable: pickable,
        all?: pickable != [] and Enum.all?(pickable, &MapSet.member?(assigns.picked, &1))
      )

    ~H"""
    <div id="teacher-table" class="ta-panel overflow-x-auto !p-0">
      <table class="table">
        <thead>
          <tr class="text-xs text-base-content/70">
            <th class="w-10">
              <input
                id="pick-all"
                type="checkbox"
                class="checkbox checkbox-sm"
                phx-click="pick-all"
                checked={@all?}
                disabled={@pickable == []}
                aria-label={gettext("Sélectionner tous les enseignants à relancer")}
              />
            </th>
            <th class="font-medium">{gettext("Enseignant")}</th>
            <th class="hidden font-medium sm:table-cell">{gettext("Cours")}</th>
            <th class="w-44 font-medium sm:w-56">{gettext("Cours commencés")}</th>
            <th :if={@competences?} class="hidden font-medium md:table-cell">
              {gettext("Compétences")}
            </th>
            <th class="hidden font-medium md:table-cell">{gettext("Dernière saisie")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@teachers == []}>
            <td colspan="6" class="py-6 text-center text-sm text-base-content/70">
              {gettext("Aucun enseignant ne correspond.")}
            </td>
          </tr>
          <tr
            :for={t <- @teachers}
            id={"teacher-#{t.id}"}
            class={["transition-colors", MapSet.member?(@picked, t.id) && "bg-warning/5"]}
          >
            <td>
              <input
                :if={t.id in @pickable}
                id={"pick-#{t.id}"}
                type="checkbox"
                class="checkbox checkbox-sm"
                phx-click="pick"
                phx-value-id={t.id}
                checked={MapSet.member?(@picked, t.id)}
                aria-label={gettext("Sélectionner %{name}", name: t.name)}
              />
            </td>
            <td class="min-w-0">
              <span class="block font-semibold">{t.name}</span>
              <span class="block text-xs text-base-content/70">{Enum.join(t.subjects, ", ")}</span>
              <span
                :if={reminded_today?(@reminders, t)}
                id={"reminded-#{t.id}"}
                class="text-xs font-semibold text-primary"
              >
                {gettext("Relancé aujourd'hui ✓")}
              </span>
              <span
                :if={t.lagging == [] and t.measurable > 0}
                class="text-xs font-semibold text-primary"
              >
                {gettext("Tout est saisi ✓")}
              </span>
            </td>
            <td class="ta-num hidden text-sm text-base-content/75 sm:table-cell">
              {ngettext("%{count} cours", "%{count} cours", t.courses)}
            </td>
            <td>
              <.progress_meter :if={t.measurable > 0} value={t.started} total={t.measurable} />
              <span :if={t.measurable == 0} class="text-xs text-base-content/70">
                {gettext("aucun élève")}
              </span>
            </td>
            <td
              :if={@competences?}
              class={[
                "hidden text-sm md:table-cell",
                if(t.competences_left == 0, do: "text-primary", else: "text-warning")
              ]}
            >
              {competences_text(t.competences_left)}
            </td>
            <td class="hidden text-sm text-base-content/75 md:table-cell">
              {last_entry(t.last_entry_at)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :competences?, :boolean, required: true

  defp subject_table(assigns) do
    ~H"""
    <div id="subject-table" class="ta-panel overflow-x-auto !p-0">
      <table class="table">
        <thead>
          <tr class="text-xs text-base-content/70">
            <th class="font-medium">{gettext("Matière")}</th>
            <th class="hidden font-medium sm:table-cell">{gettext("Classes")}</th>
            <th class="w-44 font-medium sm:w-56">{gettext("Cours commencés")}</th>
            <th class="hidden font-medium sm:table-cell">{gettext("Complets")}</th>
            <th :if={@competences?} class="hidden font-medium md:table-cell">
              {gettext("Compétences")}
            </th>
            <th class="hidden font-medium md:table-cell">{gettext("Dernière saisie")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan="6" class="py-6 text-center text-sm text-base-content/70">
              {gettext("Aucune matière ne correspond.")}
            </td>
          </tr>
          <tr :for={r <- @rows} id={"subject-#{subject_dom_id(r.key)}"}>
            <td class="min-w-0">
              <span class="block font-semibold">{r.label}</span>
              <span class="block text-xs text-base-content/70">
                {if r.teachers == [],
                  do: gettext("sans enseignant"),
                  else: Enum.join(r.teachers, ", ")}
              </span>
            </td>
            <td class="ta-num hidden text-sm text-base-content/75 sm:table-cell">{r.courses}</td>
            <td>
              <.progress_meter :if={r.measurable > 0} value={r.started} total={r.measurable} />
              <span :if={r.measurable == 0} class="text-xs text-base-content/70">
                {gettext("aucun élève")}
              </span>
            </td>
            <td class="ta-num hidden text-sm text-base-content/75 sm:table-cell">
              {r.complete} / {r.measurable}
            </td>
            <td
              :if={@competences?}
              class={[
                "hidden text-sm md:table-cell",
                if(r.competences_left == 0, do: "text-primary", else: "text-warning")
              ]}
            >
              {competences_text(r.competences_left)}
            </td>
            <td class="hidden text-sm text-base-content/75 md:table-cell">
              {last_entry(r.last_entry_at)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # A catalog subject's key is its id; a free-text one is its label.
  defp subject_dom_id(key), do: :erlang.phash2(key) |> Integer.to_string()

  defp competences_text(0), do: gettext("Toutes ✓")

  defp competences_text(n),
    do: ngettext("%{count} à saisir", "%{count} à saisir", n)

  attr :grid, :map, required: true
  attr :rows, :list, required: true
  attr :competences, :map, default: nil
  attr :reminders, :map, required: true
  attr :detail, :map, default: nil

  defp class_grid(assigns) do
    ~H"""
    <div class="ta-panel flex min-w-0 flex-col gap-2.5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="ta-eyebrow">{gettext("Classes × disciplines")}</h2>
        <div class="flex flex-wrap gap-3 text-xs text-base-content/70">
          <span class="flex items-center gap-1.5">
            <i class="size-2.5 rounded-sm bg-primary/60"></i>{gettext("Complet")}
          </span>
          <span class="flex items-center gap-1.5">
            <i class="size-2.5 rounded-sm bg-warning/60"></i>{gettext("En cours")}
          </span>
          <span class="flex items-center gap-1.5">
            <i class="size-2.5 rounded-sm bg-error/60"></i>{gettext("Rien saisi")}
          </span>
          <span :if={@competences} class="flex items-center gap-1.5">
            <i class="size-1.5 rounded-full bg-base-content/80"></i>{gettext("Compétence à saisir")}
          </span>
        </div>
      </div>

      <p :if={@rows == []} class="py-2 text-sm text-base-content/70">
        {gettext("Aucune classe ne correspond.")}
      </p>

      <%!-- Phone: one row per class, its unfinished subjects listed with a direct « Relancer ». --%>
      <div id="entry-list" class="-mx-1 flex flex-col sm:hidden">
        <div
          :for={row <- @rows}
          id={"entry-row-#{row.class_group.id}"}
          class="ta-row-rule flex flex-col gap-1.5 px-1 py-2.5 last:border-b-0"
        >
          <% open = to_complete(row, @grid.subjects, @competences) %>
          <span class="flex items-center justify-between gap-2">
            <span class="font-semibold">{row.class_group.label}</span>
            <span :if={open == []} class="text-sm text-primary">{gettext("Complet")} ✓</span>
            <span :if={open != []} class="text-sm text-base-content/70">
              {ngettext(
                "%{count} matière à compléter",
                "%{count} matières à compléter",
                length(open)
              )}
            </span>
          </span>
          <span
            :for={{subject, cell} <- open}
            class="flex min-h-11 items-center gap-2 text-sm"
          >
            <span class={["size-2.5 shrink-0 rounded-sm", swatch(cell.pct)]}></span>
            <span class="min-w-0 flex-1 truncate">
              <span class="font-medium">{subject.label}</span>
              <span class="ta-num text-base-content/70">· {pct_text(cell.pct)}</span>
              <span class="block whitespace-normal text-xs text-base-content/70">
                {teacher_name(cell.teacher)}
                <span :if={@reminders[cell.teaching_context.id]}>
                  · {gettext("relancé le %{date}",
                    date: Dates.short(@reminders[cell.teaching_context.id])
                  )}
                </span>
                <span :if={Pilotage.competence_missing?(@competences, cell)} class="text-warning">
                  · {gettext("compétence à saisir")}
                </span>
              </span>
            </span>
            <button
              :if={(cell.pct < 100 and cell.teacher) && !@reminders[cell.teaching_context.id]}
              type="button"
              class="btn btn-sm btn-outline"
              phx-click="remind"
              phx-value-tc={cell.teaching_context.id}
            >
              {gettext("Relancer")}
            </button>
          </span>
        </div>
      </div>

      <div class="hidden overflow-x-auto sm:block">
        <div
          id="entry-grid"
          class="grid gap-[3px]"
          style={grid_style(length(@grid.subjects))}
        >
          <span></span>
          <span
            :for={subject <- @grid.subjects}
            data-subject
            title={subject.label}
            class="ta-num truncate py-1 text-center text-[0.64rem] font-semibold text-base-content/80"
          >
            {subject.code}
          </span>

          <%= for row <- @rows do %>
            <span class="flex items-center truncate text-sm font-semibold">
              {row.class_group.label}
            </span>
            <.grid_cell
              :for={{subject, n} <- Enum.with_index(@grid.subjects)}
              id={"cell-#{row.class_group.id}-#{n}"}
              cg_id={row.class_group.id}
              col={n}
              cell={row.cells[subject.key]}
              reminded={
                row.cells[subject.key] &&
                  @reminders[row.cells[subject.key].teaching_context.id]
              }
              no_competence={Pilotage.competence_missing?(@competences, row.cells[subject.key])}
              title={"#{row.class_group.label} · #{subject.label}"}
              selected={
                @detail != nil and @detail.cg_id == row.class_group.id and
                  @detail.col == n
              }
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :detail, :map, required: true
  attr :competences, :map, default: nil
  attr :reminders, :map, required: true

  defp cell_detail(assigns) do
    ~H"""
    <div id="cell-detail" class="ta-panel flex flex-col gap-2 !border-primary">
      <span class="ta-eyebrow">
        {@detail.class_group.label} · {@detail.subject.label}
      </span>
      <span class="font-display text-[1.15rem] font-semibold">
        {teacher_name(@detail.cell.teacher)}
      </span>
      <.detail_line
        label={gettext("Notes saisies")}
        value={"#{@detail.cell.entered} / #{@detail.cell.expected}"}
      />
      <.detail_line
        label={gettext("Évaluations")}
        value={
          if @detail.cell.assessments == [],
            do: "—",
            else: Enum.join(@detail.cell.assessments, " · ")
        }
      />
      <.detail_line
        label={gettext("Dernière saisie")}
        value={last_entry(@detail.cell.last_entry_at)}
      />
      <div :if={@competences} id="detail-competence" class="flex flex-col gap-0.5 text-sm">
        <span class="text-base-content/70">{gettext("Compétence")}</span>
        <%= if text = @competences[@detail.cell.teaching_context.id] do %>
          <span>{text}</span>
        <% else %>
          <span class="font-semibold text-warning">{gettext("à saisir")}</span>
        <% end %>
      </div>
      <.detail_line
        :if={@reminders[@detail.cell.teaching_context.id]}
        id="reminded-on"
        label={gettext("Relancé")}
        value={Dates.short(@reminders[@detail.cell.teaching_context.id])}
      />
      <button
        :if={
          @detail.cell.pct < 100 and
            @reminders[@detail.cell.teaching_context.id] != Reference.today()
        }
        id="remind-course"
        type="button"
        phx-click="remind"
        phx-value-tc={@detail.cell.teaching_context.id}
        phx-disable-with={gettext("Envoi…")}
        class="btn btn-warning btn-sm mt-1"
      >
        <.icon name="hero-bell-alert" class="size-4" />
        {gettext("Relancer")}
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :cg_id, :string, required: true
  attr :col, :integer, required: true
  attr :cell, :map, default: nil
  attr :title, :string, required: true
  attr :selected, :boolean, default: false
  attr :reminded, :any, default: nil
  attr :no_competence, :boolean, default: false

  defp grid_cell(%{cell: nil} = assigns) do
    ~H"""
    <span
      id={@id}
      title={gettext("Non enseignée")}
      class="h-9 rounded-md border border-dashed border-base-300"
    ></span>
    """
  end

  defp grid_cell(%{cell: %{pct: nil}} = assigns) do
    ~H"""
    <span
      id={@id}
      title={@title <> " · " <> gettext("aucun élève")}
      class="ta-num flex h-9 items-center justify-center rounded-md bg-base-300/40 text-xs text-base-content/70"
    >
      ·
    </span>
    """
  end

  defp grid_cell(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click="select"
      phx-value-cg={@cg_id}
      phx-value-col={@col}
      data-tc={@cell.teaching_context.id}
      data-reminded={@reminded != nil}
      title={
        @title <> " · " <> teacher_name(@cell.teacher) <>
          if(@reminded,
            do: " · " <> gettext("relancé le %{date}", date: Dates.short(@reminded)),
            else: ""
          ) <>
          if(@no_competence, do: " · " <> gettext("compétence à saisir"), else: "")
      }
      aria-pressed={to_string(@selected)}
      class={[
        "ta-num relative h-9 cursor-pointer rounded-md text-xs font-semibold transition-colors hover:ring-1 hover:ring-base-content/50",
        cell_bg(@cell.pct),
        @selected && "ring-2 ring-base-content hover:ring-2 hover:ring-base-content"
      ]}
    >
      {pct_text(@cell.pct)}<.icon
        :if={@reminded}
        name="hero-bell-alert"
        class="ml-0.5 size-3 align-[-1px] text-base-content/70"
      />
      <span
        :if={@no_competence}
        data-role="no-competence"
        class="absolute right-1 top-1 size-1.5 rounded-full bg-base-content/80"
      ></span>
    </button>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_line(assigns) do
    ~H"""
    <div id={@id} class="flex justify-between gap-2 text-sm">
      <span class="text-base-content/70">{@label}</span>
      <span class="ta-num text-right">{@value}</span>
    </div>
    """
  end

  defp cell_bg(100), do: "bg-primary/20 text-primary hover:bg-primary/30"
  defp cell_bg(0), do: "bg-error/20 text-error hover:bg-error/30"
  defp cell_bg(_), do: "bg-warning/20 text-warning hover:bg-warning/30"

  # A class's subjects still to complete (cells with students): marks under 100 %, or
  # the APC competence not written.
  defp to_complete(row, subjects, competences) do
    for subject <- subjects,
        cell = row.cells[subject.key],
        cell && cell.pct != nil,
        cell.pct < 100 or Pilotage.competence_missing?(competences, cell),
        do: {subject, cell}
  end

  defp swatch(0), do: "bg-error/60"
  defp swatch(100), do: "bg-primary/60"
  defp swatch(_pct), do: "bg-warning/60"

  defp pct_text(100), do: "✓"
  defp pct_text(pct), do: "#{pct} %"

  defp grid_style(n),
    do: "grid-template-columns: 72px repeat(#{n}, minmax(56px, 1fr)); min-width: #{72 + n * 59}px"

  # "Séquence 2 · saisie jusqu'au ven. 2 oct. (J-3)"; past the deadline the J-n part is dropped.
  defp eyebrow_text(%{grade_entry_deadline: %Date{} = deadline} = seq) do
    case Date.diff(deadline, Reference.today()) do
      days when days >= 0 ->
        gettext("Séquence %{n} · saisie jusqu'au %{date} (J-%{d})",
          n: seq.number,
          date: Dates.short(deadline),
          d: days
        )

      _ ->
        gettext("Séquence %{n} · clôturée le %{date}", n: seq.number, date: Dates.short(deadline))
    end
  end

  defp eyebrow_text(seq), do: gettext("Censorat · Séquence %{n}", n: seq.number)

  defp teacher_name(nil), do: "—"
  defp teacher_name(teacher), do: User.display_name(teacher)

  defp last_entry(nil), do: "—"

  defp last_entry(%DateTime{} = at) do
    case Date.diff(Reference.today(), Reference.today(at)) do
      days when days <= 0 -> gettext("aujourd'hui")
      1 -> gettext("hier")
      days -> gettext("il y a %{n} j", n: days)
    end
  end
end
