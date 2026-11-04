defmodule TeacherAssistantWeb.School.CorrectionsLive do
  @moduledoc """
  Démarches → Corrections de notes (spec D3c; UX refonte 2026-11-03): a teacher's
  requests to change locked marks, and the form to file one. Visiting marks the
  decisions as seen (menu badge).

  On phones the form is there straight away under a task header: the evaluation
  as a card with « Changer » (a sheet listing the others), the students as a
  tappable list with their current mark — every class of a combined course —, a
  large « 8 → [12] », the motive chips and a sticky « Envoyer au censeur · Élève
  8 → 12 ». From `sm` the form opens with « Nouvelle demande ». « Mes demandes »
  are cards.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment}
  alias TeacherAssistant.Academics.{MarkCorrectionMotive, MarkEntry, SchoolTemplates}
  alias TeacherAssistantWeb.Drawer
  alias TeacherAssistantWeb.School.LessonComponents

  # Students shown before « Voir les N élèves ».
  @first_students 5

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    :ok = Assessment.mark_corrections_seen(scope)

    labels =
      if scope.current_workspace,
        do: scope |> Curriculum.list_units_for_scope() |> LessonComponents.course_labels(),
        else: %{}

    {:ok,
     socket
     |> assign(:page_title, gettext("Corrections de notes"))
     |> assign(:columns, scope |> Assessment.list_correctable_assessments() |> columns(labels))
     |> assign(picking?: false, all_students?: false)
     |> load_requests()}
  end

  # One column per evaluation as the teacher sees it: a combined course's evaluation
  # is one real assessment per member class.
  defp columns(assessments, labels) do
    # `list_correctable_assessments/1` reads oldest first: keep that order.
    assessments
    |> Enum.chunk_by(&column_key/1)
    |> Enum.reduce([], fn [first | _] = chunk, acc ->
      case List.keyfind(acc, column_key(first), 0) do
        nil -> [{column_key(first), chunk} | acc]
        {key, rows} -> List.keyreplace(acc, key, 0, {key, rows ++ chunk})
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {_key, members} -> column(members, labels) end)
  end

  defp column_key(%{teaching_context: tc} = a),
    do: {tc.combined_course_id || tc.id, a.sequence_id, a.label}

  defp column([first | _] = members, labels) do
    tc = first.teaching_context

    unit =
      case tc.combined_course_id do
        nil -> "#{tc.subject} · #{tc.class_group.label}"
        id -> Map.get(labels, id) || tc.subject
      end

    %{
      id: first.id,
      ids: Enum.map(members, & &1.id),
      title: "#{unit} · #{gettext("Séq. %{n}", n: first.sequence.number)} · #{first.label}",
      assessments:
        Enum.sort_by(members, &SchoolTemplates.class_sort_key(&1.teaching_context.class_group))
    }
  end

  def handle_params(params, _uri, socket) do
    %{columns: columns} = socket.assigns
    column = Enum.find(columns, &(params["assessment"] in &1.ids)) || List.first(columns)

    {:noreply,
     socket
     |> assign(
       show_form?: socket.assigns.live_action == :new,
       picking?: false,
       all_students?: false
     )
     |> assign(:column, column)
     |> load_students()
     |> assign_form(%{"assessment_id" => column && column.id, "motive" => "erreur_saisie"})}
  end

  def handle_event("open_form", _params, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/corrections/new")}

  def handle_event("pick_assessment", _params, socket),
    do: {:noreply, assign(socket, :picking?, true)}

  def handle_event("close_picker", _params, socket),
    do: {:noreply, assign(socket, :picking?, false)}

  def handle_event("all_students", _params, socket),
    do: {:noreply, assign(socket, :all_students?, true)}

  def handle_event("validate", %{"correction" => params}, socket),
    do: {:noreply, assign_form(socket, params)}

  def handle_event("request", %{"correction" => params}, socket) do
    case MarkEntry.parse(params["value"]) do
      {:ok, entry} ->
        request(socket, params, entry)

      :error ->
        {:noreply,
         assign_form(socket, params,
           value: gettext("Note invalide : un nombre, abs, abj ou vide.")
         )}
    end
  end

  defp request(socket, params, entry) do
    {status, score} =
      case entry do
        :blank -> {nil, nil}
        {:graded, score} -> {:graded, score}
        absence -> {absence, nil}
      end

    attrs = %{
      # The student's own class's assessment (a combined course has one per class).
      assessment_id:
        assessment_of(socket.assigns.students, params["student_id"]) || params["assessment_id"],
      student_id: params["student_id"],
      requested_status: status,
      requested_score: score,
      motive: params["motive"]
    }

    case Assessment.request_correction(socket.assigns.current_scope, attrs) do
      {:ok, _correction} ->
        {:noreply,
         socket
         |> put_flash(:info, sent_message(socket.assigns.current_scope))
         |> load_requests()
         |> push_patch(to: ~p"/school/corrections")}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _error} ->
        {:noreply,
         assign_form(socket, params,
           value:
             gettext(
               "Demande impossible : la note doit être valide, différente de la note actuelle, et sans demande déjà en attente."
             )
         )}
    end
  end

  defp assessment_of(students, student_id),
    do: Enum.find_value(students, &(&1.id == student_id && &1.assessment_id))

  defp sent_message(scope) do
    case Assessment.censeur_name(scope) do
      nil -> gettext("Demande envoyée au censeur.")
      name -> gettext("Demande envoyée à %{name} (censeur).", name: name)
    end
  end

  defp load_requests(socket),
    do: assign(socket, :requests, Assessment.list_my_corrections(socket.assigns.current_scope))

  # The column's students, every member class, each with its class's assessment and
  # its current mark.
  defp load_students(%{assigns: %{column: nil}} = socket),
    do: assign(socket, students: [], current_marks: %{})

  defp load_students(%{assigns: %{column: column, current_scope: scope}} = socket) do
    {students, marks} =
      Enum.reduce(column.assessments, {[], %{}}, fn a, {students, marks} ->
        cg = a.teaching_context.class_group

        rows =
          for s <- Enrollment.list_students(scope, cg),
              do: %{id: s.id, full_name: s.full_name, class_label: cg.label, assessment_id: a.id}

        {students ++ rows,
         Map.merge(marks, Map.new(Assessment.list_marks(scope, a), &{&1.student_id, &1}))}
      end)

    assign(socket, students: students, current_marks: marks)
  end

  defp assign_form(socket, params, errors \\ []) do
    errors = Enum.map(errors, fn {field, message} -> {field, {message, []}} end)
    assign(socket, :form, to_form(params, as: :correction, errors: errors))
  end

  defp current_mark(marks, student_id) do
    case marks[student_id] do
      nil -> MarkEntry.format(nil, nil)
      mark -> MarkEntry.format(mark.status, mark.score)
    end
  end

  # « 08 → 13 » once a student and a readable value are chosen.
  defp change(%{current_marks: marks, form: form}) do
    with id when id not in [nil, ""] <- form[:student_id].value,
         raw when raw not in [nil, ""] <- form[:value].value,
         {:ok, entry} <- MarkEntry.parse(raw) do
      requested =
        case entry do
          :blank -> MarkEntry.format(nil, nil)
          {:graded, score} -> MarkEntry.format(:graded, score)
          status -> MarkEntry.format(status, nil)
        end

      "#{current_mark(marks, id)} → #{requested}"
    else
      _incomplete -> nil
    end
  end

  # « Envoyer au censeur · Bassong Clarisse 8 → 12 »
  defp submit_label(assigns, change) do
    student = Enum.find(assigns.students, &(&1.id == assigns.form[:student_id].value))

    case {student, change} do
      {%{full_name: name}, change} when is_binary(change) ->
        gettext("Envoyer au censeur") <> " · " <> name <> " " <> change

      _ ->
        gettext("Envoyer au censeur")
    end
  end

  # The first students, plus the chosen one when further down.
  defp shown_students(students, _selected, true), do: students

  defp shown_students(students, selected, false) do
    first = Enum.take(students, @first_students)

    case Enum.find(students, &(&1.id == selected)) do
      nil -> first
      student -> if student in first, do: first, else: first ++ [student]
    end
  end

  # « Par <name> le <date> », then « · <note> » when the admin left one.
  defp decision_line(%{status: :pending}), do: gettext("Envoyée au censeur")

  defp decision_line(c) do
    by =
      gettext("Par %{name} le %{date}",
        name: if(c.decider, do: User.display_name(c.decider), else: "—"),
        date: c.decided_at && Calendar.strftime(c.decided_at, "%d/%m")
      )

    if c.decision_note in [nil, ""], do: by, else: by <> " · " <> c.decision_note
  end

  def render(assigns) do
    change = change(assigns)

    assigns =
      assign(assigns,
        change: change,
        submit_label: submit_label(assigns, change),
        combined?: assigns.column != nil and length(assigns.column.assessments) > 1
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path} immersive>
      <section id="corrections-page" class="mx-auto max-w-3xl space-y-6 pb-24 sm:pb-0">
        <.back_header
          task
          back={~p"/school/today"}
          back_label={gettext("Ma journée")}
          title={gettext("Corrections de notes")}
          subtitle={gettext("Le censeur valide · tout est tracé")}
        >
          <:actions>
            <button
              :if={!@show_form?}
              id="new-correction-button"
              type="button"
              phx-click="open_form"
              class="btn btn-primary btn-sm hidden sm:inline-flex"
            >
              <.icon name="hero-plus" class="size-4" /> {gettext("Nouvelle demande")}
            </button>
          </:actions>
        </.back_header>

        <section
          id="new-correction-panel"
          class={[
            "space-y-4 sm:rounded-box sm:border sm:border-base-300 sm:bg-base-100 sm:p-4",
            !@show_form? && "sm:hidden"
          ]}
        >
          <h2 class="hidden text-lg font-semibold sm:block">{gettext("Nouvelle demande")}</h2>
          <p :if={@columns == []} class="ta-leaf text-sm text-base-content/70">
            {gettext("Aucune évaluation verrouillée dans vos cours.")}
          </p>

          <.form
            :if={@column}
            for={@form}
            id="new-correction-form"
            phx-change="validate"
            phx-submit="request"
            class="space-y-5"
          >
            <input type="hidden" name={@form[:assessment_id].name} value={@column.id} />

            <div
              id="correction-assessment"
              class="ta-panel flex items-center gap-3"
            >
              <span class="flex min-w-0 flex-1 flex-col">
                <span class="text-xs text-base-content/70">{gettext("Évaluation")}</span>
                <span class="text-[0.95rem] font-semibold">{@column.title}</span>
              </span>
              <button
                :if={length(@columns) > 1}
                id="change-assessment"
                type="button"
                phx-click="pick_assessment"
                class="btn btn-ghost btn-sm shrink-0 text-primary"
              >
                {gettext("Changer")}
              </button>
            </div>

            <fieldset id="correction-students" class="space-y-1.5">
              <legend class="mb-1.5 px-1 text-xs font-semibold uppercase tracking-wide text-base-content/70">
                {gettext("Élève")}
              </legend>
              <div class="ta-section">
                <label
                  :for={s <- shown_students(@students, @form[:student_id].value, @all_students?)}
                  id={"student-#{s.id}"}
                  class={[
                    "ta-list-row cursor-pointer",
                    @form[:student_id].value == s.id && "ta-list-row--selected"
                  ]}
                >
                  <input
                    type="radio"
                    name={@form[:student_id].name}
                    value={s.id}
                    checked={@form[:student_id].value == s.id}
                    class="sr-only"
                  />
                  <span class="min-w-0 flex-1 truncate text-[0.92rem]">
                    {s.full_name}<span :if={@combined?} class="text-base-content/70"> · {s.class_label}</span>
                  </span>
                  <span class="ta-num shrink-0 text-[0.95rem] font-semibold">
                    {current_mark(@current_marks, s.id)}
                  </span>
                </label>
              </div>
              <button
                :if={
                  !@all_students? and
                    length(@students) >
                      length(shown_students(@students, @form[:student_id].value, false))
                }
                id="all-students"
                type="button"
                phx-click="all_students"
                class="btn btn-ghost btn-sm w-full text-primary"
              >
                {gettext("Voir les %{count} élèves", count: length(@students))}
              </button>
            </fieldset>

            <label for="correction-value" class="ta-panel flex items-center gap-3">
              <span class="flex-1 text-sm text-base-content/70">{gettext("Nouvelle note")}</span>
              <span class="ta-num text-2xl font-semibold text-base-content/70">
                {if @form[:student_id].value,
                  do: current_mark(@current_marks, @form[:student_id].value),
                  else: "—"}
              </span>
              <.icon name="hero-arrow-right" class="size-4 text-base-content/70" />
              <input
                id="correction-value"
                name={@form[:value].name}
                value={@form[:value].value}
                inputmode="decimal"
                autocomplete="off"
                aria-label={gettext("Nouvelle note (0–20, abs, abj ou vide)")}
                class="input ta-num h-14 w-24 text-center text-2xl font-semibold"
              />
            </label>
            <p
              :for={msg <- Enum.map(@form[:value].errors, &translate_error/1)}
              class="text-sm text-error"
            >
              {msg}
            </p>

            <fieldset class="space-y-1.5">
              <legend class="mb-1.5 px-1 text-xs font-semibold uppercase tracking-wide text-base-content/70">
                {gettext("Motif")}
              </legend>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={motive <- MarkCorrectionMotive.offered()}
                  class={[
                    "btn btn-sm rounded-full transition",
                    if(@form[:motive].value == to_string(motive),
                      do: "btn-primary",
                      else: "btn-outline border-base-300"
                    )
                  ]}
                >
                  <input
                    type="radio"
                    name={@form[:motive].name}
                    value={motive}
                    checked={@form[:motive].value == to_string(motive)}
                    class="sr-only"
                  />
                  {MarkCorrectionMotive.label(motive)}
                </label>
              </div>
            </fieldset>

            <p
              :if={@change}
              id="correction-hint"
              class="ta-num hidden text-sm text-base-content/70 sm:block"
            >
              {@change} · {gettext("Le bulletin n'est recalculé qu'après validation.")}
            </p>

            <div class="fixed inset-x-0 bottom-0 z-20 border-t border-base-300 bg-base-200/95 px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3 backdrop-blur sm:static sm:border-0 sm:bg-transparent sm:p-0">
              <button
                id="correction-submit"
                type="submit"
                class="btn btn-primary h-12 w-full sm:w-auto"
              >
                <span class="truncate">{@submit_label}</span>
              </button>
            </div>
          </.form>
        </section>

        <section id="my-requests" class="space-y-2">
          <h2 class="px-1 text-xs font-semibold uppercase tracking-wide text-base-content/70">
            {gettext("Mes demandes")}
          </h2>
          <p :if={@requests == []} class="ta-leaf text-sm text-base-content/70">
            {gettext("Aucune demande pour l'instant.")}
          </p>
          <ul id="corrections-list" class="space-y-2">
            <li :for={c <- @requests} id={"correction-#{c.id}"} class="ta-panel flex flex-col gap-1">
              <div class="flex items-center gap-3">
                <span class="min-w-0 flex-1 truncate text-[0.92rem] font-semibold">
                  {c.student.full_name} · {c.assessment.teaching_context.class_group.label}
                </span>
                <span class="ta-num shrink-0 text-[0.95rem] font-semibold">
                  {MarkEntry.format(c.current_status, c.current_score)} → {MarkEntry.format(
                    c.requested_status,
                    c.requested_score
                  )}
                </span>
                <.correction_status status={c.status} />
              </div>
              <p class="ta-num text-xs text-base-content/70">
                {Calendar.strftime(c.inserted_at, "%d/%m")} · {c.assessment.label}
              </p>
              <p data-role="decision" class="text-xs text-base-content/70">{decision_line(c)}</p>
            </li>
          </ul>
        </section>
      </section>

      <Drawer.drawer
        :if={@picking?}
        id="assessment-picker"
        title={gettext("Évaluation")}
        on_close={JS.push("close_picker")}
      >
        <ul class="ta-section">
          <li :for={col <- @columns}>
            <.list_row
              id={"pick-#{col.id}"}
              patch={~p"/school/corrections/new?assessment=#{col.id}"}
              title={col.title}
              selected={@column && col.id == @column.id}
            />
          </li>
        </ul>
      </Drawer.drawer>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  def correction_status(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm shrink-0",
      case @status do
        :pending -> "badge-warning"
        :approved -> "badge-success"
        :refused -> "badge-error"
      end
    ]}>
      {case @status do
        :pending -> gettext("En attente")
        :approved -> gettext("Acceptée")
        :refused -> gettext("Refusée")
      end}
    </span>
    """
  end
end
