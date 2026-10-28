defmodule TeacherAssistantWeb.School.SequenceTrackingLive do
  @moduledoc """
  Censorat → Suivi des séquences (spec F, N05): per séquence, how complete each
  course's mark entry is, as a classes × subjects grid, the detail of a selected
  course and the teachers whose courses are not yet fully entered.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Assessment, Organization}
  alias TeacherAssistant.Academics.{Lock, Reference}
  alias TeacherAssistantWeb.Dates

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
           year: year,
           sequences: sequences,
           seq: nil,
           grid: nil,
           selected: nil,
           reminders: %{},
           competences: nil
         )}
    end
  end

  def handle_params(params, _uri, socket) do
    %{sequences: sequences, year: year, current_scope: scope} = socket.assigns

    case pick_sequence(sequences, params["seq"]) do
      nil ->
        {:noreply,
         assign(socket, seq: nil, grid: nil, selected: nil, reminders: %{}, competences: nil)}

      seq ->
        grid = Assessment.sequence_entry_grid(scope, year, seq)

        {:noreply,
         assign(socket,
           seq: seq,
           grid: grid,
           selected: default_selection(grid),
           reminders: Assessment.reminder_dates(scope, seq),
           competences: Assessment.competences_due(scope, seq, context_ids(grid))
         )}
    end
  end

  defp context_ids(grid) do
    for row <- grid.rows, %{teaching_context: tc} <- Map.values(row.cells), do: tc.id
  end

  # An id that is not one of this year's séquences (another year, garbage) falls
  # back to the default one.
  defp pick_sequence(sequences, id) when is_binary(id) do
    Enum.find(sequences, &(&1.id == id)) || pick_sequence(sequences, nil)
  end

  defp pick_sequence(sequences, _id),
    do: Assessment.default_sequence(sequences, Reference.today())

  def handle_event("select", %{"cg" => cg_id, "col" => col}, socket) do
    with {n, ""} <- Integer.parse(col),
         %{} = detail <- detail(socket.assigns.grid, cg_id, n) do
      {:noreply, assign(socket, :selected, detail)}
    else
      _ -> {:noreply, socket}
    end
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

  def handle_event("remind-late", _params, socket) do
    %{year: year, seq: seq, current_scope: scope} = socket.assigns
    {:ok, sent} = Assessment.remind_late(scope, year, seq)

    {:noreply,
     socket
     |> put_flash(:info, sent_message(sent))
     |> assign(:reminders, Assessment.reminder_dates(scope, seq))}
  end

  def handle_event("remind-teacher", %{"teacher" => teacher_id}, socket) do
    %{grid: grid, year: year, seq: seq, current_scope: scope} = socket.assigns

    # Never trust the client id: only a teacher listed as late on screen is reminded.
    if grid && Enum.any?(grid.late, &(&1.teacher_id == teacher_id)) do
      {:ok, sent} = Assessment.remind_teacher(scope, year, seq, teacher_id)

      {:noreply,
       socket
       |> put_flash(:info, sent_message(sent))
       |> assign(:reminders, Assessment.reminder_dates(scope, seq))}
    else
      {:noreply, socket}
    end
  end

  defp sent_message(0),
    do: gettext("Aucune nouvelle relance : chaque retard a déjà été relancé aujourd'hui.")

  defp sent_message(sent),
    do: ngettext("%{count} rappel envoyé.", "%{count} rappels envoyés.", sent)

  defp reminded_today?(reminders, late),
    do: Enum.all?(late.courses, &(reminders[&1.tc_id] == Reference.today()))

  defp seq_state(seq, today) do
    cond do
      Lock.locked?(seq, today) -> :closed
      Date.compare(seq.start_date, today) != :gt -> :current
      true -> :future
    end
  end

  defp tab_label(seq, :closed), do: gettext("Séq. %{n} · close", n: seq.number)
  defp tab_label(seq, :current), do: gettext("Séq. %{n} · en cours", n: seq.number)
  defp tab_label(seq, :future), do: gettext("Séq. %{n}", n: seq.number)

  # "Boulangerie · 3e A (50 %), 4e B (0 %)": the lagging courses of a teacher, by subject.
  defp course_groups(courses) do
    courses
    |> Enum.group_by(& &1.subject)
    |> Enum.map(fn {subject, list} ->
      {subject, Enum.map_join(list, ", ", &"#{&1.class} (#{&1.pct} %)")}
    end)
    |> Enum.sort()
  end

  defp lagging_cell(nil, _tc_id), do: nil

  defp lagging_cell(grid, tc_id) do
    grid.rows
    |> Enum.flat_map(&Map.values(&1.cells))
    |> Enum.find(fn
      %{pct: pct, teaching_context: %{id: ^tc_id}} when is_integer(pct) and pct < 100 -> true
      _ -> false
    end)
  end

  # As in the mockup a course is selected on arrival: the first one not complete, else the first.
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
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="sequence-tracking" class="flex flex-col gap-5">
        <.page_header
          eyebrow={
            if @seq,
              do: eyebrow_text(@seq),
              else: gettext("Censorat")
          }
          title={gettext("Suivi de la saisie des notes")}
        >
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
          <nav
            id="seq-tabs"
            aria-label={gettext("Séquences")}
            class="flex flex-wrap gap-2"
          >
            <.link
              :for={s <- @sequences}
              id={"seq-tab-#{s.id}"}
              patch={~p"/school/sequences?seq=#{s.id}"}
              aria-current={s.id == @seq.id && "page"}
              class={[
                "rounded-full border px-3 py-2 text-sm font-medium transition-colors",
                if(s.id == @seq.id,
                  do: "border-primary bg-primary text-primary-content",
                  else: "border-base-300 text-base-content/70 hover:border-primary"
                )
              ]}
            >
              {tab_label(s, seq_state(s, Reference.today()))}
            </.link>
          </nav>

          <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
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
                </div>
              </div>

              <p
                :if={@competences && @grid.subjects != []}
                id="competence-count"
                class={[
                  "flex items-center gap-1.5 text-xs",
                  if(competence_gaps(@grid, @competences) > 0,
                    do: "font-semibold text-warning",
                    else: "text-base-content/70"
                  )
                ]}
              >
                <i class="size-1.5 rounded-full bg-base-content/80"></i>
                <%= case competence_gaps(@grid, @competences) do %>
                  <% 0 -> %>
                    {gettext("Toutes les compétences de la séquence sont renseignées")}
                  <% n -> %>
                    {ngettext("%{count} cours sans compétence", "%{count} cours sans compétence", n)}
                <% end %>
              </p>

              <p :if={@grid.subjects == []} class="text-sm text-base-content/70">
                {gettext("Aucun cours n'est encore attribué pour cette année.")}
              </p>

              <%!-- Phone: one row per class, its unfinished subjects listed with a direct « Relancer ». --%>
              <div :if={@grid.subjects != []} id="entry-list" class="-mx-1 flex flex-col sm:hidden">
                <div
                  :for={row <- @grid.rows}
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
                      <span :if={no_competence?(@competences, cell)} class="text-warning">
                        · {gettext("compétence à saisir")}
                      </span>
                      <span class="block truncate text-xs text-base-content/70">
                        {teacher_name(cell.teacher)}
                        <span :if={@reminders[cell.teaching_context.id]}>
                          · {gettext("relancé le %{date}",
                            date: Dates.short(@reminders[cell.teaching_context.id])
                          )}
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

              <div :if={@grid.subjects != []} class="hidden overflow-x-auto sm:block">
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

                  <%= for row <- @grid.rows do %>
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
                      no_competence={no_competence?(@competences, row.cells[subject.key])}
                      title={"#{row.class_group.label} · #{subject.label}"}
                      selected={
                        @selected != nil and @selected.cg_id == row.class_group.id and
                          @selected.col == n
                      }
                    />
                  <% end %>
                </div>
              </div>
            </div>

            <div class="flex min-w-0 flex-col gap-3">
              <div
                :if={@selected}
                id="cell-detail"
                class="ta-panel flex flex-col gap-2 !border-primary"
              >
                <span class="ta-eyebrow">
                  {@selected.class_group.label} · {@selected.subject.label}
                </span>
                <span class="font-display text-[1.15rem] font-semibold">
                  {teacher_name(@selected.cell.teacher)}
                </span>
                <.detail_line
                  label={gettext("Notes saisies")}
                  value={"#{@selected.cell.entered} / #{@selected.cell.expected}"}
                />
                <.detail_line
                  label={gettext("Évaluations")}
                  value={
                    if @selected.cell.assessments == [],
                      do: "—",
                      else: Enum.join(@selected.cell.assessments, " · ")
                  }
                />
                <.detail_line
                  label={gettext("Dernière saisie")}
                  value={last_entry(@selected.cell.last_entry_at)}
                />
                <.detail_line
                  :if={@competences}
                  id="detail-competence"
                  label={gettext("Compétence")}
                  value={@competences[@selected.cell.teaching_context.id] || gettext("à saisir")}
                />
                <.detail_line
                  :if={@reminders[@selected.cell.teaching_context.id]}
                  id="reminded-on"
                  label={gettext("Relancé")}
                  value={Dates.short(@reminders[@selected.cell.teaching_context.id])}
                />
                <button
                  :if={
                    @selected.cell.pct < 100 and
                      @reminders[@selected.cell.teaching_context.id] != Reference.today()
                  }
                  id="remind-course"
                  type="button"
                  phx-click="remind"
                  phx-value-tc={@selected.cell.teaching_context.id}
                  phx-disable-with={gettext("Envoi…")}
                  class="btn btn-warning btn-sm mt-1"
                >
                  <.icon name="hero-bell-alert" class="size-4" />
                  {gettext("Relancer")}
                </button>
              </div>

              <div id="late-teachers" class="ta-panel flex flex-col gap-1">
                <h2 class="ta-eyebrow">
                  {gettext("À relancer · %{n}", n: length(@grid.late))}
                </h2>
                <p :if={@grid.late == []} class="py-2 text-sm text-base-content/70">
                  {gettext("Personne : tous les cours sont saisis à 100 %.")}
                </p>
                <ul :if={@grid.late != []} class="flex flex-col">
                  <li
                    :for={late <- @grid.late}
                    id={"late-#{late.teacher_id}"}
                    class="ta-row-rule flex items-start justify-between gap-3 py-[7px]"
                  >
                    <div class="flex min-w-0 flex-col">
                      <span class="text-[0.88rem] font-semibold">{teacher_name(late.teacher)}</span>
                      <span
                        :for={{subject, detail} <- course_groups(late.courses)}
                        class="text-[0.74rem] text-base-content/75"
                      >
                        {subject} · {detail}
                      </span>
                    </div>
                    <button
                      :if={not reminded_today?(@reminders, late)}
                      id={"remind-teacher-#{late.teacher_id}"}
                      type="button"
                      phx-click="remind-teacher"
                      phx-value-teacher={late.teacher_id}
                      phx-disable-with={gettext("Envoi…")}
                      class="btn btn-outline btn-warning btn-xs shrink-0"
                    >
                      {gettext("Relancer")}
                    </button>
                    <span
                      :if={reminded_today?(@reminders, late)}
                      id={"remind-teacher-#{late.teacher_id}"}
                      class="shrink-0 pt-1 text-xs font-semibold text-primary"
                    >
                      {gettext("Relancé ✓")}
                    </span>
                  </li>
                </ul>
                <button
                  :if={@grid.late != []}
                  id="remind-late"
                  type="button"
                  phx-click="remind-late"
                  phx-disable-with={gettext("Envoi…")}
                  class="btn btn-outline btn-warning btn-sm mt-2"
                >
                  <.icon name="hero-bell-alert" class="size-4" />
                  {gettext("Relancer tous")}
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
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
        cell.pct < 100 or no_competence?(competences, cell),
        do: {subject, cell}
  end

  # A course with students whose APC competence is due and not yet written.
  defp no_competence?(nil, _cell), do: false
  defp no_competence?(_competences, nil), do: false
  defp no_competence?(_competences, %{pct: nil}), do: false
  defp no_competence?(competences, cell), do: is_nil(competences[cell.teaching_context.id])

  defp competence_gaps(grid, competences) do
    Enum.count(
      for(row <- grid.rows, cell <- Map.values(row.cells), do: cell),
      &no_competence?(competences, &1)
    )
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
