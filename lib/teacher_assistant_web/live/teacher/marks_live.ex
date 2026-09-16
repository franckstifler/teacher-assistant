defmodule TeacherAssistantWeb.Teacher.MarksLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => ctx_id} = params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, ctx} <- owned_context(ws, ctx_id),
         false <- is_nil(ctx.class_group_id),
         {:ok, cg} <- Academics.fetch_owned_class_group(ctx.class_group_id, ws) do
      year = Academics.current_academic_year(ws)
      sequences = if year, do: Academics.list_sequences(year), else: []
      seq = pick(sequences, params["seq"])
      assessments = if seq, do: Academics.list_assessments(ctx, seq), else: []
      assessment = pick(assessments, params["assessment"])
      students = Academics.list_students(cg)

      {:ok,
       socket
       |> assign(:ws, ws)
       |> assign(:ctx, ctx)
       |> assign(:sequences, sequences)
       |> assign(:seq, seq)
       |> assign(:assessments, assessments)
       |> assign(:assessment, assessment)
       |> assign(:students, students)
       |> assign(:scores, existing_scores(assessment))
       |> assign(:sibling_scores, sibling_scores(ctx, seq))
       |> assign(:new_assessment_form, to_form(%{}, as: :assessment))}
    else
      # true => context owned but has no class group (go set up the roster); anything else => not found / not owned
      true ->
        {:ok, push_navigate(socket, to: ~p"/teacher/contexts/#{ctx_id}/roster")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp owned_context(nil, _ctx_id), do: :error
  defp owned_context(ws, ctx_id), do: Academics.fetch_owned_teaching_context(ctx_id, ws)

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  defp existing_scores(nil), do: %{}

  defp existing_scores(assessment) do
    assessment
    |> Academics.list_marks()
    |> Map.new(fn m -> {m.student_id, (m.score && Decimal.to_string(m.score)) || ""} end)
  end

  # %{ {student_id, assessment_id} => score } for every assessment of the séquence
  defp sibling_scores(_ctx, nil), do: %{}

  defp sibling_scores(ctx, seq) do
    ctx
    |> Academics.list_marks_for_context_sequence(seq)
    |> Map.new(fn m -> {{m.student_id, m.assessment_id}, m.score} end)
  end

  defp entered_count(scores), do: Enum.count(scores, fn {_id, v} -> v not in [nil, ""] end)

  defp preview_average(_students, nil, _scores), do: nil

  defp preview_average(students, assessment, scores) do
    marks =
      Enum.map(students, fn s ->
        %{
          assessment_id: assessment.id,
          student_id: s.id,
          score: parse_score(Map.get(scores, s.id))
        }
      end)

    summary =
      TeacherAssistant.Academics.Marks.summarize(
        Enum.map(students, fn s -> %{id: s.id, sex: s.sex} end),
        [%{id: assessment.id, weight: assessment.weight, max_score: assessment.max_score}],
        marks
      )

    summary.class_average
  end

  defp fmt_avg(nil), do: "—"
  defp fmt_avg(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  def handle_event("select_seq", %{"seq" => seq_id}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq_id}")}
  end

  def handle_event("select_assessment", %{"assessment" => aid}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{socket.assigns.seq.id}&assessment=#{aid}"
     )}
  end

  def handle_event("new_assessment", %{"assessment" => p}, socket) do
    with %{} = seq when not is_nil(seq) <- socket.assigns.seq,
         {:ok, a} <- Academics.create_assessment(socket.assigns.ctx, seq, %{label: p["label"]}) do
      {:noreply,
       push_patch(socket,
         to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}"
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  def handle_event("preview", %{"scores" => scores}, socket) do
    {:noreply, assign(socket, :scores, Map.new(scores, fn {k, v} -> {k, v} end))}
  end

  def handle_event("save", %{"scores" => scores}, socket) do
    entries =
      Enum.map(socket.assigns.students, fn s ->
        %{student_id: s.id, score: parse_score(Map.get(scores, s.id))}
      end)

    case Academics.upsert_marks(socket.assigns.assessment, entries) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Marks saved"))
         |> assign(:scores, existing_scores(socket.assigns.assessment))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not save marks"))}
    end
  end

  def handle_params(params, _uri, socket) do
    seq = pick(socket.assigns.sequences, params["seq"])
    assessments = if seq, do: Academics.list_assessments(socket.assigns.ctx, seq), else: []
    assessment = pick(assessments, params["assessment"])

    {:noreply,
     socket
     |> assign(:seq, seq)
     |> assign(:assessments, assessments)
     |> assign(:assessment, assessment)
     |> assign(:scores, existing_scores(assessment))
     |> assign(:sibling_scores, sibling_scores(socket.assigns.ctx, seq))}
  end

  defp parse_score(nil), do: nil
  defp parse_score(""), do: nil

  defp parse_score(v) do
    case Decimal.parse(v) do
      {d, _} -> d
      :error -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks" class="mx-auto max-w-3xl space-y-4">
        <.page_header eyebrow={gettext("Marks")} title={"#{@ctx.subject} · #{@ctx.level}"} />

        <div
          id="marks-toolbar"
          class="ta-leaf sticky top-16 z-10 flex flex-wrap items-end gap-2 backdrop-blur"
        >
          <form id="seq-select" phx-change="select_seq" class="min-w-36 flex-1">
            <.input
              type="select"
              name="seq"
              value={@seq && @seq.id}
              label={gettext("Séquence")}
              options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
            />
          </form>

          <form
            :if={@seq}
            id="assessment-select"
            phx-change="select_assessment"
            class="min-w-36 flex-1"
          >
            <.input
              type="select"
              name="assessment"
              value={@assessment && @assessment.id}
              label={gettext("Assessment")}
              options={for a <- @assessments, do: {a.label, a.id}}
            />
          </form>

          <.form
            :if={@seq}
            for={@new_assessment_form}
            id="new-assessment-form"
            phx-submit="new_assessment"
            class="flex flex-1 items-end gap-2"
          >
            <.input field={@new_assessment_form[:label]} placeholder={gettext("New assessment")} />
            <.button type="submit" class="btn btn-outline btn-sm">{gettext("Add")}</.button>
          </.form>
        </div>

        <%= if @assessment do %>
          <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
            <p id="marks-progress" class="ta-num text-base-content/70">
              {gettext("%{entered} of %{total} entered",
                entered: entered_count(@scores),
                total: length(@students)
              )}
            </p>
            <p id="marks-average-preview" class="ta-num font-semibold">
              {gettext("Class average")}:
              <span class="text-primary">
                {fmt_avg(preview_average(@students, @assessment, @scores))}
              </span>
            </p>
          </div>
          <p class="text-xs text-base-content/55">
            {gettext("Blank = absent. Marks are out of 20.")}
          </p>

          <.form
            for={to_form(%{}, as: :scores)}
            id="marks-form"
            phx-change="preview"
            phx-submit="save"
            class="space-y-2"
          >
            <div id="marks-sheet-header" class="hidden items-center gap-2 px-3 md:flex">
              <span class="ta-eyebrow flex-1">{gettext("Élève")}</span>
              <span
                :for={a <- @assessments}
                :if={a.id != @assessment.id}
                class="ta-eyebrow w-16 text-right"
              >
                {a.label}
              </span>
              <span class="ta-eyebrow w-24 text-right">{@assessment.label}</span>
            </div>

            <div
              :for={s <- @students}
              id={"mark-row-#{s.id}"}
              class="ta-leaf flex items-center justify-between gap-2"
            >
              <span class="flex-1">{s.full_name}</span>
              <span
                :for={a <- @assessments}
                :if={a.id != @assessment.id}
                class="ta-num hidden w-16 text-right text-sm text-base-content/55 md:inline-block"
              >
                {fmt_avg(@sibling_scores[{s.id, a.id}])}
              </span>
              <input
                id={"mark-input-#{s.id}"}
                type="number"
                step="0.25"
                min="0"
                max="20"
                inputmode="decimal"
                aria-label={s.full_name}
                placeholder={gettext("Abs")}
                name={"scores[#{s.id}]"}
                value={Map.get(@scores, s.id, "")}
                class="ta-num input input-bordered h-11 w-24 text-right"
              />
            </div>
            <.button id="marks-submit" type="submit" class="btn btn-primary w-full">
              {gettext("Save marks")}
            </.button>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
