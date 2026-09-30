defmodule TeacherAssistantWeb.School.SequenceTrackingLive do
  @moduledoc """
  Censorat → Suivi des séquences (spec F, N05): per séquence, how complete each
  course's mark entry is, as a classes × subjects grid with KPI tiles, the detail
  of a selected course and the teachers who have entered nothing yet.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Assessment, Organization}
  alias TeacherAssistant.Academics.Reference

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
         assign(socket, year: year, sequences: sequences, seq: nil, grid: nil, selected: nil)}
    end
  end

  def handle_params(params, _uri, socket) do
    %{sequences: sequences, year: year, current_scope: scope} = socket.assigns

    case pick_sequence(sequences, params["seq"]) do
      nil ->
        {:noreply, assign(socket, seq: nil, grid: nil, selected: nil)}

      seq ->
        {:noreply,
         assign(socket,
           seq: seq,
           grid: Assessment.sequence_entry_grid(scope, year, seq),
           selected: nil
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

  def handle_event("select", %{"cg" => cg_id, "col" => col}, socket) do
    with {n, ""} <- Integer.parse(col),
         %{} = detail <- detail(socket.assigns.grid, cg_id, n) do
      {:noreply, assign(socket, :selected, detail)}
    else
      _ -> {:noreply, socket}
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
        <.page_header eyebrow={gettext("Censorat")} title={gettext("Suivi des séquences")}>
          <:actions :if={@year}>
            <span class="ta-num inline-flex items-center rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold text-base-content/70">
              {@year.name}
            </span>
          </:actions>
        </.page_header>

        <div
          :if={@grid == nil}
          id="no-sequences"
          class="ta-leaf flex items-start gap-3 text-sm text-base-content/80"
        >
          <.icon name="hero-calendar-days" class="size-5 shrink-0 text-base-content/50" />
          <p>
            {gettext(
              "Aucune séquence pour l'année en cours. Définissez le calendrier dans les paramètres pour suivre la saisie des notes."
            )}
          </p>
        </div>

        <%= if @grid do %>
          <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <.kpi
              id="kpi-overall"
              label={gettext("Saisie globale")}
              value={if @grid.overall_pct, do: "#{@grid.overall_pct} %", else: "—"}
              sub={gettext("toutes classes, toutes disciplines")}
              tone="text-warning"
            />
            <.kpi
              id="kpi-complete"
              label={gettext("Classes complètes")}
              value={"#{elem(@grid.complete_classes, 0)} / #{elem(@grid.complete_classes, 1)}"}
              sub={gettext("prêtes pour le conseil")}
              tone="text-primary"
            />
            <.kpi
              id="kpi-late"
              label={gettext("Enseignants à relancer")}
              value={to_string(late_teacher_count(@grid.late))}
              sub={gettext("aucune note saisie")}
              tone="text-error"
            />
            <.kpi
              id="kpi-council"
              label={gettext("Conseils de classe")}
              value={
                if @grid.council_date,
                  do: Calendar.strftime(@grid.council_date, "%d/%m"),
                  else: "—"
              }
              sub={council_sub(@seq)}
              tone="text-base-content"
            />
          </div>

          <nav
            id="seq-tabs"
            aria-label={gettext("Séquences")}
            class="flex flex-wrap gap-2"
          >
            <.link
              :for={s <- @sequences}
              id={"seq-tab-#{s.number}"}
              patch={~p"/school/sequences?seq=#{s.id}"}
              aria-current={s.id == @seq.id && "page"}
              class={[
                "ta-num rounded-full border px-3 py-1 text-xs font-semibold transition-colors hover:border-warning",
                if(s.id == @seq.id,
                  do: "border-warning bg-warning/15 text-warning",
                  else: "border-base-300 text-base-content/70"
                )
              ]}
            >
              S{s.number}
            </.link>
          </nav>

          <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
            <div class="flex min-w-0 flex-col gap-3 rounded-box border border-base-300 bg-base-200 px-4 py-3.5">
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

              <p :if={@grid.subjects == []} class="text-sm text-base-content/60">
                {gettext("Aucun cours n'est encore attribué pour cette année.")}
              </p>

              <div :if={@grid.subjects != []} class="overflow-x-auto">
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
                    class="ta-num truncate py-1 text-center text-[0.64rem] font-semibold text-base-content/60"
                  >
                    {subject.label}
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
                class="flex flex-col gap-2 rounded-box border border-primary bg-base-200 px-4 py-3.5"
              >
                <span class="ta-eyebrow">
                  {@selected.class_group.label} · {@selected.subject.label}
                </span>
                <span class="font-display text-lg font-semibold">
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
              </div>

              <div
                id="late-teachers"
                class="flex flex-col gap-1 rounded-box border border-base-300 bg-base-200 px-4 py-3.5"
              >
                <h2 class="ta-eyebrow">{gettext("À relancer")}</h2>
                <p :if={@grid.late == []} class="py-2 text-sm text-base-content/60">
                  {gettext("Personne : chaque cours a au moins une note saisie.")}
                </p>
                <div
                  :for={late <- @grid.late}
                  class="flex flex-col border-b border-base-300 py-2 last:border-b-0"
                >
                  <span class="text-sm font-semibold">{teacher_name(late.teacher)}</span>
                  <span class="text-xs text-base-content/60">
                    {gettext("%{subject} · %{classes} · rien saisi",
                      subject: late.subject,
                      classes: Enum.join(late.classes, ", ")
                    )}
                  </span>
                </div>
                <p class="mt-2 flex items-center gap-1.5 text-xs text-base-content/50">
                  <.icon name="hero-bell" class="size-3.5" />
                  {gettext("Les relances arrivent avec les notifications.")}
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, required: true

  defp kpi(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-1 rounded-box border border-base-300 bg-base-200 px-4 py-3">
      <span class="ta-num text-[0.65rem] font-semibold uppercase tracking-[0.12em] text-base-content/60">
        {@label}
      </span>
      <span class={["ta-num text-2xl font-semibold leading-tight sm:text-3xl", @tone]}>
        {@value}
      </span>
      <span :if={@sub} class="text-xs text-base-content/60">{@sub}</span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :cg_id, :string, required: true
  attr :col, :integer, required: true
  attr :cell, :map, default: nil
  attr :title, :string, required: true
  attr :selected, :boolean, default: false

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
      class="ta-num flex h-9 items-center justify-center rounded-md bg-base-300/40 text-xs text-base-content/50"
    >
      —
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
      title={@title <> " · " <> teacher_name(@cell.teacher)}
      aria-pressed={to_string(@selected)}
      class={[
        "ta-num h-9 cursor-pointer rounded-md text-xs font-semibold text-base-content transition-colors hover:ring-1 hover:ring-base-content/50",
        cell_bg(@cell.pct),
        @selected && "ring-2 ring-base-content hover:ring-2 hover:ring-base-content"
      ]}
    >
      {@cell.pct}%
    </button>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_line(assigns) do
    ~H"""
    <div class="flex justify-between gap-2 text-sm">
      <span class="text-base-content/70">{@label}</span>
      <span class="ta-num text-right">{@value}</span>
    </div>
    """
  end

  defp cell_bg(100), do: "bg-primary/30 hover:bg-primary/40"
  defp cell_bg(0), do: "bg-error/40 hover:bg-error/50"
  defp cell_bg(_), do: "bg-warning/30 hover:bg-warning/40"

  defp grid_style(n),
    do: "grid-template-columns: 72px repeat(#{n}, minmax(56px, 1fr)); min-width: #{72 + n * 59}px"

  defp late_teacher_count(late),
    do: late |> Enum.uniq_by(&(&1.teacher && &1.teacher.id)) |> length()

  defp council_sub(%{term: %{position: position}}),
    do: gettext("Trimestre %{n}", n: position)

  defp council_sub(_seq), do: nil

  defp teacher_name(nil), do: "—"
  defp teacher_name(teacher), do: to_string(teacher.name || teacher.email)

  defp last_entry(nil), do: "—"

  defp last_entry(%DateTime{} = at) do
    case Date.diff(Reference.today(), Reference.today(at)) do
      days when days <= 0 -> gettext("aujourd'hui")
      1 -> gettext("hier")
      days -> gettext("il y a %{n} j", n: days)
    end
  end
end
