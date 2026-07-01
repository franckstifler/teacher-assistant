defmodule TeacherAssistantWeb.Teacher.MarksSummaryLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Marks

  def mount(%{"id" => ctx_id} = params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, ctx} <- owned_context(ws, ctx_id),
         false <- is_nil(ctx.class_group_id),
         {:ok, cg} <- Academics.fetch_owned_class_group(ctx.class_group_id, ws) do
      year = Academics.current_academic_year(ws)
      sequences = if year, do: Academics.list_sequences(year), else: []
      seq = pick(sequences, params["seq"]) || List.first(sequences)

      students = Academics.list_students(cg)

      summary =
        if seq do
          assessments = Academics.list_assessments(ctx, seq)
          marks = Academics.list_marks_for_context_sequence(ctx, seq)

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

      {:ok,
       socket
       |> assign(:ctx, ctx)
       |> assign(:sequences, sequences)
       |> assign(:seq, seq)
       |> assign(:students, students)
       |> assign(:summary, summary)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp owned_context(nil, _ctx_id), do: :error
  defp owned_context(ws, ctx_id), do: Academics.fetch_owned_teaching_context(ctx_id, ws)

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp pct(rate), do: "#{round(rate * 100)}%"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks-summary" class="mx-auto max-w-md space-y-4">
        <header>
          <p class="ta-eyebrow">{gettext("Séquence results")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{@ctx.subject} · {@ctx.level}</h1>
        </header>

        <%= if @summary do %>
          <div class="grid grid-cols-2 gap-2">
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Class average")}</p>
              <p id="summary-class-average" class="text-2xl font-bold">
                {fmt(@summary.class_average)}
              </p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Pass rate")}</p>
              <p id="summary-pass-rate" class="text-2xl font-bold">{pct(@summary.pass_rate)}</p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Highest / lowest")}</p>
              <p class="text-lg">{fmt(@summary.highest)} / {fmt(@summary.lowest)}</p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Girls / boys pass")}</p>
              <p class="text-lg">
                {pct(@summary.by_sex.f.pass_rate)} / {pct(@summary.by_sex.m.pass_rate)}
              </p>
            </div>
          </div>

          <ul class="space-y-1">
            <li
              :for={s <- @students}
              id={"summary-row-#{s.id}"}
              class="ta-leaf flex items-center justify-between"
            >
              <span>{s.full_name}</span>
              <span class="font-mono">
                {fmt(@summary.per_student[s.id].average)}
                <span :if={@summary.per_student[s.id].rank} class="opacity-60">
                  ({@summary.per_student[s.id].rank})
                </span>
              </span>
            </li>
          </ul>
        <% else %>
          <p class="ta-leaf">{gettext("No séquences yet — set up the school year first.")}</p>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
