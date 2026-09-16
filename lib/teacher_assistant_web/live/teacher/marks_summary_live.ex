defmodule TeacherAssistantWeb.Teacher.MarksSummaryLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Marks

  @mention_order [:excellent, :tres_bien, :bien, :assez_bien, :passable, nil]

  def mount(%{"id" => ctx_id} = params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, ctx} <- owned_context(ws, ctx_id),
         false <- is_nil(ctx.class_group_id),
         {:ok, cg} <- Academics.fetch_owned_class_group(ctx.class_group_id, ws) do
      year = Academics.current_academic_year(ws)
      sequences = if year, do: Academics.list_sequences(year), else: []
      seq = pick(sequences, params["seq"]) || List.first(sequences)
      students = Academics.list_students(cg)

      {:ok,
       socket
       |> assign(:ctx, ctx)
       |> assign(:sequences, sequences)
       |> assign(:seq, seq)
       |> assign(:students, students)
       |> assign_summary()}
    else
      # true => context owned but has no class group (go set up the roster); anything else => not found / not owned
      true ->
        {:ok, push_navigate(socket, to: ~p"/teacher/contexts/#{ctx_id}/roster")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  def handle_params(params, _uri, socket) do
    seq = pick(socket.assigns.sequences, params["seq"]) || List.first(socket.assigns.sequences)
    {:noreply, socket |> assign(:seq, seq) |> assign_summary()}
  end

  def handle_event("select_seq", %{"seq" => seq_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks/summary?seq=#{seq_id}"
     )}
  end

  defp assign_summary(socket) do
    %{ctx: ctx, seq: seq, students: students} = socket.assigns

    summary =
      if seq do
        assessments = Academics.list_assessments(ctx, seq)
        marks = Academics.list_marks_for_context_sequence(ctx, seq)

        if assessments == [] do
          nil
        else
          Marks.summarize(
            Enum.map(students, fn s -> %{id: s.id, sex: s.sex} end),
            Enum.map(assessments, fn a ->
              %{id: a.id, weight: a.weight, max_score: a.max_score}
            end),
            Enum.map(marks, fn m ->
              %{assessment_id: m.assessment_id, student_id: m.student_id, score: m.score}
            end)
          )
        end
      end

    assign(socket, :summary, summary)
  end

  defp owned_context(nil, _ctx_id), do: :error
  defp owned_context(ws, ctx_id), do: Academics.fetch_owned_teaching_context(ctx_id, ws)

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp pct(rate), do: "#{round(rate * 100)}%"

  defp mention_distribution(summary) do
    freq =
      summary.per_student
      |> Map.values()
      |> Enum.reject(&is_nil(&1.average))
      |> Enum.frequencies_by(& &1.mention)

    for m <- @mention_order, count = Map.get(freq, m, 0), count > 0, do: {m, count}
  end

  defp missing_count(students, summary), do: length(students) - summary.graded_count

  defp bar_width(%Decimal{} = avg), do: "#{avg |> Decimal.mult(5) |> Decimal.round(0)}%"
  defp bar_width(rate) when is_float(rate), do: "#{round(rate * 100)}%"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks-summary" class="mx-auto max-w-2xl space-y-4">
        <.page_header eyebrow={gettext("Séquence results")} title={"#{@ctx.subject} · #{@ctx.level}"}>
          <:actions>
            <form :if={@sequences != []} id="summary-seq-select" phx-change="select_seq">
              <.input
                type="select"
                name="seq"
                value={@seq && @seq.id}
                options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
              />
            </form>
          </:actions>
        </.page_header>

        <%= if @summary do %>
          <div id="summary-stats" class="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <div id="summary-class-average" class="contents">
              <.stat
                label={gettext("Class average")}
                value={fmt(@summary.class_average)}
                suffix="/20"
                tone={:primary}
              />
            </div>
            <div id="summary-pass-rate" class="contents">
              <.stat label={gettext("Pass rate")} value={pct(@summary.pass_rate)} />
            </div>
            <.stat label={gettext("Highest")} value={fmt(@summary.highest)} suffix="/20" />
            <.stat label={gettext("Lowest")} value={fmt(@summary.lowest)} suffix="/20" />
          </div>

          <div id="summary-mentions" class="flex flex-wrap items-center gap-2">
            <span
              :for={{mention, count} <- mention_distribution(@summary)}
              class="badge badge-soft gap-1"
            >
              <.mention_badge mention={mention} />
              <span class="ta-num">×{count}</span>
            </span>
          </div>

          <div id="summary-sex-bars" class="ta-leaf space-y-2">
            <p class="ta-eyebrow">{gettext("Pass rate — filles / garçons")}</p>
            <div
              :for={
                {label, stats} <-
                  [{gettext("Filles"), @summary.by_sex.f}, {gettext("Garçons"), @summary.by_sex.m}]
              }
              class="flex items-center gap-2 text-sm"
            >
              <span class="w-20 shrink-0 text-base-content/70">{label}</span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-primary"
                  style={"width: #{bar_width(stats.pass_rate)}"}
                >
                </div>
              </div>
              <span class="ta-num w-12 text-right">{pct(stats.pass_rate)}</span>
            </div>
          </div>

          <p
            :if={missing_count(@students, @summary) > 0}
            id="summary-missing"
            class="flex items-center gap-2 text-sm text-warning"
          >
            <.icon name="hero-exclamation-triangle" class="size-4" />
            {gettext("%{count} student(s) without marks in this séquence",
              count: missing_count(@students, @summary)
            )}
          </p>

          <table id="summary-table" class="w-full border-separate border-spacing-y-1">
            <caption class="sr-only">{gettext("Per-student results")}</caption>
            <thead class="hidden md:table-header-group">
              <tr class="text-left">
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Rang")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Élève")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Moyenne")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Mention")}</th>
              </tr>
            </thead>
            <tbody class="block space-y-1 md:table-row-group">
              <tr :for={s <- @students} id={"summary-row-#{s.id}"} class="ta-leaf block md:table-row">
                <td class="ta-num hidden text-base-content/60 md:table-cell md:px-3 md:py-2">
                  {@summary.per_student[s.id].rank || "—"}
                </td>
                <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
                  <span>{s.full_name}</span>
                  <span class="ta-num font-mono md:hidden">
                    {fmt(@summary.per_student[s.id].average)}
                    <span :if={@summary.per_student[s.id].rank} class="opacity-60">
                      ({@summary.per_student[s.id].rank})
                    </span>
                  </span>
                </td>
                <td class="hidden md:table-cell md:px-3 md:py-2">
                  <span class="flex items-center gap-2">
                    <span class="ta-num font-mono">{fmt(@summary.per_student[s.id].average)}</span>
                    <span
                      :if={@summary.per_student[s.id].average}
                      class="h-1.5 w-16 overflow-hidden rounded-full bg-base-300"
                    >
                      <span
                        class="block h-full rounded-full bg-primary"
                        style={"width: #{bar_width(@summary.per_student[s.id].average)}"}
                      >
                      </span>
                    </span>
                  </span>
                </td>
                <td class="block md:table-cell md:px-3 md:py-2">
                  <.mention_badge
                    :if={@summary.per_student[s.id].average}
                    mention={@summary.per_student[s.id].mention}
                  />
                  <span :if={is_nil(@summary.per_student[s.id].average)} class="text-base-content/40">
                    —
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        <% else %>
          <p :if={@sequences == []} class="ta-leaf">
            {gettext("No séquences yet — set up the school year first.")}
          </p>
          <.empty_state
            :if={@sequences != []}
            icon="hero-pencil-square"
            title={gettext("No marks in this séquence yet")}
            message={gettext("Enter marks for an assessment to see the séquence results.")}
          >
            <:action>
              <.link
                navigate={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{@seq && @seq.id}"}
                class="btn btn-primary btn-sm"
              >
                {gettext("Enter marks")}
              </.link>
            </:action>
          </.empty_state>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
