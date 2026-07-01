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
     |> assign(:scores, existing_scores(assessment))}
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
      <section id="teacher-marks" class="mx-auto max-w-md space-y-4">
        <.page_header eyebrow={gettext("Marks")} title={"#{@ctx.subject} · #{@ctx.level}"} />

        <form id="seq-select" phx-change="select_seq">
          <.input
            type="select"
            name="seq"
            value={@seq && @seq.id}
            label={gettext("Séquence")}
            options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
          />
        </form>

        <%= if @seq do %>
          <form id="assessment-select" phx-change="select_assessment">
            <.input
              type="select"
              name="assessment"
              value={@assessment && @assessment.id}
              label={gettext("Assessment")}
              options={for a <- @assessments, do: {a.label, a.id}}
            />
          </form>

          <.form
            for={@new_assessment_form}
            id="new-assessment-form"
            phx-submit="new_assessment"
            class="flex gap-2"
          >
            <.input field={@new_assessment_form[:label]} placeholder={gettext("New assessment")} />
            <.button type="submit" class="btn btn-outline btn-sm">{gettext("Add")}</.button>
          </.form>
        <% end %>

        <%= if @assessment do %>
          <.form for={to_form(%{}, as: :scores)} id="marks-form" phx-submit="save" class="space-y-2">
            <div
              :for={s <- @students}
              id={"mark-row-#{s.id}"}
              class="ta-leaf flex items-center justify-between gap-2"
            >
              <span class="flex-1">{s.full_name}</span>
              <input
                id={"mark-input-#{s.id}"}
                type="number"
                step="0.25"
                min="0"
                max="20"
                inputmode="decimal"
                aria-label={s.full_name}
                name={"scores[#{s.id}]"}
                value={Map.get(@scores, s.id, "")}
                class="input input-bordered w-24"
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
