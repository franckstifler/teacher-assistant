defmodule TeacherAssistantWeb.Teacher.MarksLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.CombinedCourse

  def mount(%{"id" => ctx_id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    ws = scope.current_workspace

    case Academics.fetch_assigned_teaching_context(ctx_id, scope) do
      {:ok, %{combined_course_id: course_id} = ctx} when not is_nil(course_id) ->
        mount_combined(ctx, course_id, params, socket, ws)

      {:ok, ctx} ->
        mount_solo(ctx, params, socket, ws)

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp mount_solo(ctx, params, socket, ws) do
    with false <- is_nil(ctx.class_group_id),
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
       |> assign(:unsaved, %{})
       |> assign(:sibling_scores, sibling_scores(ctx, seq))
       |> assign(:new_assessment_form, to_form(%{}, as: :assessment))}
    else
      # true => context owned but has no class group (go set up the roster); anything else => not found / not owned
      true ->
        {:ok, push_navigate(socket, to: ~p"/teacher/contexts/#{ctx.id}/roster")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  # Combined mode: the mounted context is a member of a `CombinedCourse`.
  # The page shows the union roster of every member class (grouped by
  # class), and the "assessment" the teacher picks is a logical column
  # backed by one real `Assessment` per member context — a student's score
  # always lands on their own class's context's assessment.
  defp mount_combined(ctx, course_id, params, socket, ws) do
    case Academics.get_course(course_id) do
      {:ok, course} ->
        year = Academics.current_academic_year(ws)
        sequences = if year, do: Academics.list_sequences(year), else: []
        seq = pick(sequences, params["seq"])
        combined = if seq, do: Academics.combined_assessments_for(course, seq), else: []
        selected = pick(combined, params["assessment"])
        groups = Academics.list_union_students(course)

        {:ok,
         socket
         |> assign(:ws, ws)
         |> assign(:ctx, ctx)
         |> assign(:course, course)
         |> assign(:groups, groups)
         |> assign(:sequences, sequences)
         |> assign(:seq, seq)
         |> assign(:combined_assessments, combined)
         |> assign(:selected, selected)
         |> assign(:scores, combined_existing_scores(selected))
         |> assign(:unsaved, %{})
         |> assign(:new_assessment_form, to_form(%{}, as: :assessment))}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  defp existing_scores(nil), do: %{}

  defp existing_scores(assessment) do
    assessment
    |> Academics.list_marks()
    |> Map.new(fn m -> {m.student_id, (m.score && Decimal.to_string(m.score)) || ""} end)
  end

  defp combined_existing_scores(nil), do: %{}

  defp combined_existing_scores(%{by_class_group_id: by_class_group_id}) do
    by_class_group_id
    |> Map.values()
    |> Enum.uniq_by(& &1.id)
    |> Enum.flat_map(&Academics.list_marks/1)
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
          score: score_or_nil(Map.get(scores, s.id))
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
    case socket.assigns[:course] do
      %CombinedCourse{} = course -> new_combined_assessment(socket, course, p["label"])
      _ -> new_solo_assessment(socket, p["label"])
    end
  end

  def handle_event("preview", %{"scores" => scores}, socket) do
    {:noreply, assign(socket, :scores, Map.new(scores, fn {k, v} -> {k, v} end))}
  end

  def handle_event("save", %{"scores" => scores}, socket) do
    if not TeacherAssistant.Accounts.Permissions.operating_allowed?(socket.assigns.current_scope) do
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("École en attente de vérification — enregistrement indisponible.")
       )}
    else
      case socket.assigns[:course] do
        %CombinedCourse{} -> save_combined(socket, scores)
        _ -> save_solo(socket, scores)
      end
    end
  end

  defp new_solo_assessment(socket, label) do
    with %{} = seq when not is_nil(seq) <- socket.assigns.seq,
         {:ok, a} <- Academics.create_assessment(socket.assigns.ctx, seq, %{label: label}) do
      {:noreply,
       push_patch(socket,
         to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}"
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  defp new_combined_assessment(socket, course, label) do
    with %{} = seq when not is_nil(seq) <- socket.assigns.seq,
         {:ok, _created} <- Academics.create_combined_assessment(course, seq, %{label: label}),
         %{id: id} <-
           course
           |> Academics.combined_assessments_for(seq)
           |> Enum.find(&(&1.label == label)) do
      {:noreply,
       push_patch(socket,
         to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{id}"
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  defp save_solo(socket, scores) do
    parsed =
      Enum.map(socket.assigns.students, fn s ->
        {s.id, parse_score(Map.get(scores, s.id))}
      end)

    if Enum.any?(parsed, fn {_id, result} -> result == :error end) do
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("Some marks aren't valid numbers — use digits only, e.g. 12 or 13,5.")
       )}
    else
      save_marks(socket, parsed)
    end
  end

  defp save_marks(socket, parsed) do
    entries = Enum.map(parsed, fn {id, {:ok, score}} -> %{student_id: id, score: score} end)

    case Academics.upsert_marks(socket.assigns.assessment, entries) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Marks saved"))
         |> assign(:unsaved, Map.delete(socket.assigns.unsaved, socket.assigns.assessment.id))
         |> assign(:scores, existing_scores(socket.assigns.assessment))}

      {:error, :out_of_range} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Marks must be between 0 and %{max}.",
             max: max_label(socket.assigns.assessment)
           )
         )}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not save marks"))}
    end
  end

  # Combined mode: each student's score is routed to *their own class's*
  # assessment — never the other member class's — via
  # `selected.by_class_group_id[class_group_id]`. Every group is upserted
  # in its own `Academics.upsert_marks/2` call, so `Mark`'s
  # `[:assessment_id, :student_id]` identity and the bulletin read path are
  # untouched: a MACO student's mark still belongs to MACO's context.
  defp save_combined(socket, scores) do
    %{groups: groups, selected: selected} = socket.assigns

    all_students = Enum.flat_map(groups, & &1.students)

    parsed =
      Enum.map(all_students, fn s ->
        {s.id, parse_score(Map.get(scores, s.id))}
      end)

    if Enum.any?(parsed, fn {_id, result} -> result == :error end) do
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("Some marks aren't valid numbers — use digits only, e.g. 12 or 13,5.")
       )}
    else
      scores_by_id = Map.new(parsed, fn {id, {:ok, score}} -> {id, score} end)

      results =
        Enum.map(groups, fn %{class_group: cg, students: students} ->
          assessment = Map.fetch!(selected.by_class_group_id, cg.id)

          entries =
            Enum.map(students, fn s -> %{student_id: s.id, score: Map.get(scores_by_id, s.id)} end)

          Academics.upsert_marks(assessment, entries)
        end)

      cond do
        Enum.all?(results, &(&1 == :ok)) ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Marks saved"))
           |> assign(:unsaved, Map.delete(socket.assigns.unsaved, selected.id))
           |> assign(:scores, combined_existing_scores(selected))}

        Enum.any?(results, &match?({:error, :out_of_range}, &1)) ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Marks must be between 0 and %{max}.", max: max_label(selected))
           )}

        true ->
          {:noreply, put_flash(socket, :error, gettext("Could not save marks"))}
      end
    end
  end

  defp max_label(%{max_score: %Decimal{} = m}), do: Decimal.to_string(m, :normal)

  def handle_params(params, _uri, socket) do
    # Preserve unsaved edits across a séquence/assessment switch: stash the
    # outgoing column, restore any previously stashed edits for the incoming one,
    # so an accidental tap on a selector never discards typed marks.
    unsaved = stash_current(socket)
    seq = pick(socket.assigns.sequences, params["seq"])

    case socket.assigns[:course] do
      %CombinedCourse{} = course ->
        combined = if seq, do: Academics.combined_assessments_for(course, seq), else: []
        selected = pick(combined, params["assessment"])

        {:noreply,
         socket
         |> assign(:seq, seq)
         |> assign(:combined_assessments, combined)
         |> assign(:selected, selected)
         |> assign(:unsaved, unsaved)
         |> assign(:scores, restore_combined_scores(selected, unsaved))}

      _ ->
        assessments = if seq, do: Academics.list_assessments(socket.assigns.ctx, seq), else: []
        assessment = pick(assessments, params["assessment"])

        {:noreply,
         socket
         |> assign(:seq, seq)
         |> assign(:assessments, assessments)
         |> assign(:assessment, assessment)
         |> assign(:unsaved, unsaved)
         |> assign(:scores, restore_scores(assessment, unsaved))
         |> assign(:sibling_scores, sibling_scores(socket.assigns.ctx, seq))}
    end
  end

  defp stash_current(socket) do
    unsaved = socket.assigns[:unsaved] || %{}

    case socket.assigns[:selected] || socket.assigns[:assessment] do
      %{id: id} -> Map.put(unsaved, id, socket.assigns[:scores] || %{})
      _ -> unsaved
    end
  end

  defp restore_scores(nil, _unsaved), do: %{}

  defp restore_scores(%{id: id} = assessment, unsaved),
    do: Map.merge(existing_scores(assessment), Map.get(unsaved, id, %{}))

  defp restore_combined_scores(nil, _unsaved), do: %{}

  defp restore_combined_scores(%{id: id} = selected, unsaved),
    do: Map.merge(combined_existing_scores(selected), Map.get(unsaved, id, %{}))

  # Parses a raw score field into {:ok, Decimal.t() | nil} — nil meaning absent —
  # or :error. Accepts a French decimal comma; rejects any non-empty value that is
  # not a clean number (e.g. "abc", "15x"), so a typo is never silently stored as
  # an absence.
  defp parse_score(nil), do: {:ok, nil}

  defp parse_score(v) do
    case v |> String.trim() |> String.replace(",", ".") do
      "" ->
        {:ok, nil}

      normalized ->
        case Decimal.parse(normalized) do
          {d, ""} -> {:ok, d}
          _ -> :error
        end
    end
  end

  defp score_or_nil(raw) do
    case parse_score(raw) do
      {:ok, d} -> d
      :error -> nil
    end
  end

  def render(%{course: %CombinedCourse{}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks" class="mx-auto max-w-3xl space-y-4">
        <.page_header eyebrow={gettext("Marks")} title={@course.label} />

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
              value={@selected && @selected.id}
              label={gettext("Assessment")}
              options={for a <- @combined_assessments, do: {a.label, a.id}}
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

        <%= if @selected do %>
          <p class="text-xs text-base-content/55">
            {gettext("Blank = absent. Marks are out of 20.")}
          </p>

          <.form
            for={to_form(%{}, as: :scores)}
            id="marks-form"
            phx-change="preview"
            phx-submit="save"
            class="space-y-4"
          >
            <div :for={group <- @groups} id={"marks-class-#{group.class_group.id}"} class="space-y-2">
              <h3 class="ta-eyebrow">{group.class_group.label}</h3>

              <div
                :for={s <- group.students}
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
                  placeholder={gettext("Abs")}
                  name={"scores[#{s.id}]"}
                  value={Map.get(@scores, s.id, "")}
                  phx-debounce="300"
                  class="ta-num input input-bordered h-11 w-24 text-right"
                />
              </div>
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
                phx-debounce="300"
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
