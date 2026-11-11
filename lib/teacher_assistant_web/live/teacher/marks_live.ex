defmodule TeacherAssistantWeb.Teacher.MarksLive do
  @moduledoc """
  « Saisie des notes » (spec 2026-10-09 §2.3, refonte 2026-11-03 Batch 1): one
  assessment column of a course, each mark saved when its box loses focus. A combined
  course shows the union roster by class; its column is one real `Assessment` per
  member class and a student's mark always lands on their own class's.

  Phones get a task page — a back-arrow header whose title opens the course picker,
  evaluation chips, a list of students and a bottom bar opening the keypad (a
  full-screen mode of this page, typing locally and saving through `save_mark`'s
  path). From `sm`, the same rows are a table with evaluation cards above and a side
  panel. New evaluations, the course and séquence pickers and the competence are
  drawers (bottom sheets on phones).
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.TeachingNav
  import TeacherAssistantWeb.Drawer
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.{CombinedCourse, EntryProgress, Marks}
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.{Lock, MarkEntry, Reference}
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.Teacher.MarksComponents

  @sheets %{
    "course" => :course,
    "seq" => :seq,
    "new_eval" => :new_eval,
    "edit_eval" => :edit_eval,
    "competence" => :competence
  }

  def mount(%{"id" => ctx_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Curriculum.fetch_assigned_teaching_context(scope, ctx_id) do
      # A8: the roster, the column and its marks are read once, on the connected render.
      {:ok, ctx} when is_nil(socket.transport_pid) ->
        {:ok,
         assign(socket,
           page_title: "#{ctx.subject} · #{gettext("Notes")}",
           loading?: true
         )}

      {:ok, %{combined_course_id: course_id} = ctx} when not is_nil(course_id) ->
        mount_combined(ctx, course_id, socket)

      {:ok, ctx} ->
        mount_solo(ctx, socket)

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp mount_solo(ctx, socket) do
    scope = socket.assigns.current_scope

    case Enrollment.fetch_owned_class_group(scope, ctx.class_group_id) do
      {:ok, cg} ->
        exempt = Curriculum.exempt_student_ids(scope, ctx)

        students =
          scope |> Enrollment.list_students(cg) |> Enum.reject(&MapSet.member?(exempt, &1.id))

        {:ok,
         socket
         |> assign(course: nil, title: "#{ctx.subject} · #{cg.label}")
         |> assign(groups: [%{class_group: cg, students: students}])
         |> mount_common(ctx)}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp mount_combined(ctx, course_id, socket) do
    scope = socket.assigns.current_scope

    case Curriculum.get_course(scope, course_id) do
      {:ok, course} ->
        groups =
          scope
          |> Curriculum.list_union_students(course)
          |> Enum.map(fn group ->
            exempt = Curriculum.exempt_student_ids(scope, group.teaching_context)
            %{group | students: Enum.reject(group.students, &MapSet.member?(exempt, &1.id))}
          end)

        {:ok,
         socket
         |> assign(course: course, title: course.label, groups: groups)
         |> mount_common(ctx)}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  defp mount_common(socket, ctx) do
    scope = socket.assigns.current_scope
    year = Organization.current_academic_year(scope)

    socket
    |> assign(:page_title, "#{socket.assigns.title} · #{gettext("Notes")}")
    |> assign(:loading?, false)
    |> assign(:ctx, ctx)
    |> assign(:grading_rules, Assessment.grading_rules(scope))
    |> assign(:sequences, if(year, do: Organization.list_sequences(scope, year), else: []))
    |> assign(:student_group, student_group(socket.assigns.groups))
    |> assign(:roster, roster(socket.assigns.groups))
    |> assign(errors: %{}, saved_at: nil, today: Reference.today())
    |> assign(:apc?, apc?(scope, socket.assigns.groups))
    |> assign(competence: nil, competence_reminder_dismissed?: false, new_competence: "")
    |> assign(sheet: nil, keypad: nil, keypad_pending?: false)
    |> assign(course_units: [], course_query: "", auto_label: nil, edit_form: nil)
    |> assign_assessment_defaults(scope)
  end

  # Spec bulletin v2 §6: the class's report cards are APC (combined course: its first class).
  defp apc?(scope, [%{class_group: cg} | _]), do: Assessment.apc?(scope, cg)
  defp apc?(_scope, _groups), do: false

  defp load_competence(%{assigns: %{apc?: true, seq: %{} = seq, ctx: ctx}} = socket) do
    texts = Assessment.sequence_competences(socket.assigns.current_scope, [ctx.id], [seq.id])
    assign(socket, :competence, texts[{ctx.id, seq.id}])
  end

  defp load_competence(socket), do: assign(socket, :competence, nil)

  defp current_unit?({:course, course}, ctx), do: course.id == ctx.combined_course_id
  defp current_unit?({:solo, tc}, ctx), do: tc.id == ctx.id

  # student id => class group id, to route a mark to the student's own class.
  defp student_group(groups),
    do: for(g <- groups, s <- g.students, into: %{}, do: {s.id, g.class_group.id})

  # Every student in page order, with their class and their number in it (from 1).
  defp roster(groups) do
    for g <- groups,
        {s, n} <- Enum.with_index(g.students, 1),
        do: %{student: s, class_group: g.class_group, n: n}
  end

  # School assessment types and default maximum for the "new assessment" form.
  defp assign_assessment_defaults(socket, scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    assign(socket,
      assessment_types: Assessment.list_assessment_types(scope),
      default_max: profile.default_max_score
    )
  end

  # Students whose make-up is still expected on the selected column (make-up rule).
  # Under the make-up rule, the students whose saved mark in the column is an absence
  # (A8: from the marks already in memory, `loaded`, never a second read of the column).
  defp assign_pending(%{assigns: %{grading_rules: %{absence: :makeup}, loaded: loaded}} = socket) do
    pending =
      for s <- all_students(socket.assigns),
          MarkEntry.parse(Map.get(loaded, s.id)) in [{:ok, :absent}, {:ok, :excused}],
          do: s.full_name

    assign(socket, :pending_makeups, pending)
  end

  defp assign_pending(socket), do: assign(socket, :pending_makeups, [])

  # "New assessment" params: drop an empty type, name it after its type when the
  # label is blank ("Devoir surveillé 2"), and keep a valid maximum (otherwise the
  # school default applies).
  defp normalize_assessment_params(params, socket) do
    type = find_type(socket, params["assessment_type_id"])

    label =
      case {String.trim(params["label"] || ""), type} do
        {"", %{} = type} -> type_label(socket, type)
        {label, _} -> label
      end

    max =
      case Curriculum.parse_coefficient(params["max_score"] || "") do
        {:ok, dec} -> dec
        :error -> nil
      end

    %{"label" => label}
    |> then(&if(type, do: Map.put(&1, "assessment_type_id", type.id), else: &1))
    |> then(&if(max, do: Map.put(&1, "max_score", max), else: &1))
  end

  defp find_type(socket, id), do: Enum.find(socket.assigns.assessment_types, &(&1.id == id))

  # « Interrogation 3 »: the type's name and its next number among the séquence's columns.
  defp type_label(socket, type), do: "#{type.name} #{next_type_number(socket, type)}"

  defp next_type_number(socket, type) do
    Enum.count(socket.assigns.columns, &String.starts_with?(&1.label, type.name)) + 1
  end

  # The séquence asked for, else the current one (the one containing today, else the
  # last started, else the first) — never none while the year has séquences.
  defp pick_seq(sequences, id),
    do: pick(sequences, id) || Assessment.default_sequence(sequences, Reference.today())

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  # The selected column's real assessments: one, or one per member class.
  defp column_assessments(nil), do: []

  defp column_assessments(%{by_class_group_id: by_cg}),
    do: by_cg |> Map.values() |> Enum.uniq_by(& &1.id)

  defp column_assessments(assessment), do: [assessment]

  # %{student_id => field text} of the stored marks.
  defp saved_marks(scope, column) do
    column
    |> column_assessments()
    |> Enum.flat_map(&Assessment.list_marks(scope, &1))
    |> Map.new(fn m -> {m.student_id, mark_field(m)} end)
  end

  # %{column_id => MapSet of the shown students with a mark}: every chip's count, in
  # one read.
  defp column_marks(scope, columns, student_group) do
    marked = Assessment.marked_students(scope, Enum.flat_map(columns, &column_assessments/1))

    Map.new(columns, fn column ->
      students =
        column
        |> column_assessments()
        |> Enum.map(&Map.get(marked, &1.id, MapSet.new()))
        |> Enum.reduce(MapSet.new(), &MapSet.union/2)
        |> MapSet.filter(&Map.has_key?(student_group, &1))

      {column.id, students}
    end)
  end

  defp mark_field(%{status: status, score: score}), do: MarkEntry.format(status, score)

  defp all_students(%{groups: groups}), do: Enum.flat_map(groups, & &1.students)

  defp entered_count(students, loaded),
    do: Enum.count(students, &(Map.get(loaded, &1.id) not in [nil, ""]))

  defp blank?(loaded, id), do: Map.get(loaded, id) in [nil, ""]

  # The first student, in page order, whose box is still empty (and not in error).
  defp next_empty_id(%{locked?: true}), do: nil
  defp next_empty_id(%{column: nil}), do: nil

  defp next_empty_id(%{roster: roster, loaded: loaded, errors: errors}) do
    Enum.find_value(roster, fn %{student: %{id: id}} ->
      if blank?(loaded, id) and not Map.has_key?(errors, id), do: id
    end)
  end

  defp preview_average(students, column, scores, rules) do
    marks =
      Enum.flat_map(students, fn s ->
        case MarkEntry.parse(Map.get(scores, s.id)) do
          {:ok, :blank} ->
            []

          :error ->
            []

          {:ok, entry} ->
            [Map.merge(%{assessment_id: column.id, student_id: s.id}, entry_mark(entry))]
        end
      end)

    summary =
      Marks.summarize(
        Enum.map(students, fn s -> %{id: s.id, sex: s.sex, name: s.full_name} end),
        [%{id: column.id, weight: column.weight, max_score: column.max_score}],
        marks,
        rules
      )

    summary.class_average
  end

  defp fmt_avg(nil), do: "—"

  defp fmt_avg(%Decimal{} = d),
    do:
      d
      |> Decimal.round(2)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

  defp low_avg?(%Decimal{} = d), do: Decimal.compare(d, 10) == :lt
  defp low_avg?(_avg), do: false

  # Blank scaffold for the "new assessment" form in combined mode. Backed by the
  # real `Assessment :create` action so the `:label` field renders as an
  # `AshPhoenix.Form` field; `as: "assessment"` keeps the posted param key
  # (`%{"assessment" => %{"label" => …}}`). In combined mode the multi-class create
  # runs through `Assessment.create_combined_assessment/4` directly (it never calls
  # `AshPhoenix.Form.submit/2` on this form), so no `prepare_source` is needed here.
  defp assessment_form(scope) do
    TeacherAssistant.Academics.Assessment
    |> AshPhoenix.Form.for_create(:create, as: "assessment", scope: scope)
    |> to_form()
  end

  # Solo mode: the "new assessment" form, with the server-controlled context/séquence
  # ids set on the changeset at build time via `prepare_source` (never merged into the
  # submitted params). The tenant and actor travel on the form's `scope:`. `seq` is a
  # *live* value, so the form is rebuilt on every `handle_params/3` and whenever the
  # drawer opens. Falls back to the plain scaffold when there's no séquence yet (the
  # drawer is only opened with one).
  defp solo_assessment_form(scope, _ctx, nil), do: assessment_form(scope)

  defp solo_assessment_form(scope, ctx, seq) do
    TeacherAssistant.Academics.Assessment
    |> AshPhoenix.Form.for_create(:create,
      as: "assessment",
      scope: scope,
      prepare_source: fn changeset ->
        changeset
        |> Ash.Changeset.change_attribute(:teaching_context_id, ctx.id)
        |> Ash.Changeset.change_attribute(:sequence_id, seq.id)
      end
    )
    |> to_form()
  end

  # Drives the `Assessment :create` action through the form built by
  # `solo_assessment_form/3`. Errors keep the original flash; on success the
  # `push_patch` re-runs `handle_params/3`, which selects the new column and — the
  # drawer's promise, « Créer et commencer la saisie » — opens the keypad (phones).
  defp new_solo_assessment(socket, params) do
    case socket.assigns.seq do
      %{} = seq ->
        case AshPhoenix.Form.submit(socket.assigns.new_assessment_form, params: params) do
          {:ok, a} ->
            {:noreply, start_entry(socket, seq, a.id)}

          {:error, form} ->
            if Authz.forbidden_form?(form),
              do: {:noreply, Authz.put_not_allowed(socket)},
              else:
                {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  defp new_combined_assessment(socket, course, params) do
    scope = socket.assigns.current_scope
    label = params["label"]

    attrs = %{
      label: label,
      assessment_type_id: params["assessment_type_id"],
      max_score: params["max_score"]
    }

    with %{} = seq when not is_nil(seq) <- socket.assigns.seq,
         {:ok, _created} <- Assessment.create_combined_assessment(scope, course, seq, attrs),
         %{id: id} <-
           scope
           |> Assessment.combined_assessments_for(course, seq)
           |> Enum.find(&(&1.label == label)) do
      {:noreply, start_entry(socket, seq, id)}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  defp start_entry(socket, seq, assessment_id) do
    socket
    |> put_new_competence(seq)
    |> assign(:keypad_pending?, true)
    |> push_patch(to: marks_path(socket, seq, assessment_id))
  end

  # The competence written in « Nouvelle évaluation » (asked there only while the
  # séquence has none): saved with the évaluation, never blocking it.
  defp put_new_competence(%{assigns: %{apc?: true, competence: nil}} = socket, seq) do
    case String.trim(socket.assigns.new_competence) do
      "" ->
        socket

      text ->
        %{current_scope: scope, ctx: ctx} = socket.assigns

        case Assessment.put_sequence_competence(scope, ctx, seq, text) do
          :ok -> socket
          {:error, _} -> put_flash(socket, :error, gettext("Compétence non enregistrée."))
        end
    end
  end

  defp put_new_competence(socket, _seq), do: socket

  defp marks_path(socket, seq, nil),
    do: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}"

  defp marks_path(socket, seq, assessment_id),
    do:
      ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{assessment_id}"

  def handle_params(_params, _uri, %{assigns: %{loading?: true}} = socket),
    do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    seq = pick_seq(socket.assigns.sequences, params["seq"])
    columns = columns(socket, seq)
    # The asked column, else the first: the sheet is never hidden behind a picker.
    column = pick(columns, params["assessment"]) || List.first(columns)
    loaded = saved_marks(scope, column)

    {:noreply,
     socket
     |> warn_dropped_errors()
     |> assign(seq: seq, upcoming?: seq != nil and Lock.not_started?(seq))
     # `locked?`: no entry at all — past the deadline, or not started yet (`upcoming?`).
     |> assign(locked?: seq != nil and (Lock.locked?(seq) or Lock.not_started?(seq)))
     |> assign(columns: columns, column: column)
     |> assign(:column_marks, column_marks(scope, columns, socket.assigns.student_group))
     |> assign(scores: loaded, loaded: loaded, errors: %{}, sheet: nil)
     |> assign(:new_assessment_form, new_assessment_form(socket, seq))
     |> open_pending_keypad()
     |> load_competence()
     |> assign_pending()}
  end

  # After « Créer et commencer la saisie »: the keypad opens on the first student.
  defp open_pending_keypad(%{assigns: %{keypad_pending?: true}} = socket) do
    first =
      case socket.assigns.roster do
        [%{student: s} | _] -> s.id
        [] -> nil
      end

    open? = not socket.assigns.locked? and socket.assigns.column != nil

    socket
    |> assign(keypad_pending?: false)
    |> assign(:keypad, if(open?, do: first))
  end

  defp open_pending_keypad(socket), do: assign(socket, :keypad, nil)

  # Valid marks are already saved; only cells still in error lose their text on a switch.
  defp warn_dropped_errors(%{assigns: %{errors: errors}} = socket) when map_size(errors) > 0 do
    put_flash(
      socket,
      :error,
      ngettext(
        "%{count} note non enregistrée abandonnée (valeur invalide).",
        "%{count} notes non enregistrées abandonnées (valeurs invalides).",
        map_size(errors)
      )
    )
  end

  defp warn_dropped_errors(socket), do: socket

  defp columns(_socket, nil), do: []

  defp columns(%{assigns: %{course: %CombinedCourse{} = course}} = socket, seq),
    do: Assessment.combined_assessments_for(socket.assigns.current_scope, course, seq)

  defp columns(socket, seq),
    do: Assessment.list_assessments(socket.assigns.current_scope, socket.assigns.ctx, seq)

  defp new_assessment_form(%{assigns: %{course: %CombinedCourse{}}} = socket, _seq),
    do: assessment_form(socket.assigns.current_scope)

  defp new_assessment_form(socket, seq),
    do: solo_assessment_form(socket.assigns.current_scope, socket.assigns.ctx, seq)

  # --- Sheets (drawers; bottom sheets on phones) -----------------------------------

  def handle_event("open_sheet", %{"sheet" => key}, socket) do
    case Map.fetch(@sheets, key) do
      {:ok, sheet} -> open_sheet(socket, sheet)
      :error -> {:noreply, socket}
    end
  end

  def handle_event("close_sheet", _params, socket), do: {:noreply, assign(socket, :sheet, nil)}

  def handle_event("course_search", %{"q" => q}, socket),
    do: {:noreply, assign(socket, :course_query, q)}

  # The type picked fills the name (« Interrogation 3 ») unless the teacher wrote one.
  def handle_event("new_eval_change", %{"assessment" => p} = params, socket) do
    {p, auto} =
      with ["assessment", "assessment_type_id"] <- params["_target"],
           %{} = type <- find_type(socket, p["assessment_type_id"]),
           true <- String.trim(p["label"] || "") in ["", socket.assigns.auto_label] do
        label = type_label(socket, type)
        {Map.put(p, "label", label), label}
      else
        _ -> {p, socket.assigns.auto_label}
      end

    form = AshPhoenix.Form.validate(socket.assigns.new_assessment_form, p, errors: false)

    {:noreply,
     assign(socket,
       new_assessment_form: form,
       auto_label: auto,
       new_competence: get_in(params, ["competence", "text"]) || socket.assigns.new_competence
     )}
  end

  def handle_event("save_competence", %{"competence" => %{"text" => text}}, socket),
    do: save_competence(socket, text)

  def handle_event("save_competence_blur", %{"value" => text}, socket) do
    if String.trim(text) == String.trim(socket.assigns.competence || ""),
      do: {:noreply, socket},
      else: save_competence(socket, text)
  end

  def handle_event("dismiss_competence_reminder", _params, socket),
    do: {:noreply, assign(socket, :competence_reminder_dismissed?, true)}

  def handle_event("new_assessment", _params, %{assigns: %{upcoming?: true}} = socket),
    do: {:noreply, put_flash(socket, :error, not_open_message())}

  def handle_event("new_assessment", _params, %{assigns: %{locked?: true}} = socket),
    do: {:noreply, put_flash(socket, :error, gettext("Séquence verrouillée."))}

  def handle_event("new_assessment", %{"assessment" => p} = params, socket) do
    socket =
      case get_in(params, ["competence", "text"]) do
        text when is_binary(text) -> assign(socket, :new_competence, text)
        _ -> socket
      end

    case socket.assigns[:course] do
      %CombinedCourse{} = course ->
        new_combined_assessment(socket, course, normalize_assessment_params(p, socket))

      _ ->
        new_solo_assessment(socket, normalize_assessment_params(p, socket))
    end
  end

  def handle_event("edit_assessment", _params, %{assigns: %{column: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("edit_assessment", %{"edit" => p}, socket) do
    case edit_attrs(p, socket) do
      {:ok, attrs} -> update_column(socket, attrs)
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  # An évaluation made before its séquence started can still go (the domain allows it).
  def handle_event(
        "delete_assessment",
        _params,
        %{assigns: %{locked?: true, upcoming?: false}} = socket
      ),
      do: {:noreply, put_flash(socket, :error, gettext("Séquence verrouillée."))}

  def handle_event("delete_assessment", _params, %{assigns: %{column: nil}} = socket),
    do: {:noreply, socket}

  # The selected column only: a combined course's goes from every member class.
  def handle_event("delete_assessment", _params, socket) do
    %{current_scope: scope, column: column, seq: seq} = socket.assigns

    case Assessment.delete_assessments(scope, column_assessments(column)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Évaluation supprimée."))
         |> push_patch(to: marks_path(socket, seq, nil))}

      {:error, :has_marks} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Cette évaluation a déjà des notes : effacez-les avant de la supprimer.")
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Impossible de supprimer l'évaluation."))}
    end
  end

  def handle_event("save_mark", %{"student" => id, "value" => raw}, socket),
    do: {:noreply, save_entry(socket, id, raw)}

  def handle_event("toggle_absent", _params, %{assigns: %{locked?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle_absent", %{"student" => id}, socket) do
    entry =
      if MarkEntry.parse(socket.assigns.loaded[id]) == {:ok, :absent}, do: :blank, else: :absent

    {:noreply, write_mark(socket, id, entry)}
  end

  # --- Keypad (phones) ---------------------------------------------------------------

  def handle_event("keypad_open", params, socket) do
    %{locked?: locked?, column: column, student_group: groups} = socket.assigns
    id = params["student"] || next_empty_id(socket.assigns)

    if locked? or column == nil or not Map.has_key?(groups, id || ""),
      do: {:noreply, socket},
      else: {:noreply, assign(socket, :keypad, id)}
  end

  # ✕ / ↑ / Suivant: save the typed value through `save_mark`'s path, then move.
  def handle_event("keypad_" <> move, %{"student" => id, "value" => raw}, socket)
      when move in ["next", "prev", "close"] do
    socket = save_entry(socket, id, raw)
    {:noreply, assign(socket, :keypad, keypad_target(socket.assigns, id, move))}
  end

  def handle_event("keypad_close", _params, socket), do: {:noreply, assign(socket, :keypad, nil)}

  defp keypad_target(%{locked?: true}, _id, _move), do: nil
  defp keypad_target(_assigns, _id, "close"), do: nil

  defp keypad_target(%{errors: errors} = assigns, id, move) do
    ids = Enum.map(assigns.roster, & &1.student.id)
    index = Enum.find_index(ids, &(&1 == id))

    cond do
      is_nil(index) -> nil
      Map.has_key?(errors, id) -> id
      move == "prev" -> Enum.at(ids, max(index - 1, 0))
      # Past the last student, the list shows what is left.
      true -> Enum.at(ids, index + 1)
    end
  end

  defp open_sheet(%{assigns: %{upcoming?: true}} = socket, :new_eval),
    do: {:noreply, put_flash(socket, :error, not_open_message())}

  defp open_sheet(%{assigns: %{locked?: true}} = socket, :new_eval),
    do: {:noreply, put_flash(socket, :error, gettext("Séquence verrouillée."))}

  defp open_sheet(socket, :new_eval) do
    {:noreply,
     assign(socket,
       sheet: :new_eval,
       auto_label: nil,
       new_competence: "",
       new_assessment_form: new_assessment_form(socket, socket.assigns.seq)
     )}
  end

  defp open_sheet(%{assigns: %{column: nil}} = socket, :edit_eval), do: {:noreply, socket}

  defp open_sheet(socket, :edit_eval) do
    column = socket.assigns.column

    form =
      to_form(%{"label" => column.label, "max_score" => MarksComponents.max_text(column)},
        as: :edit
      )

    {:noreply, assign(socket, sheet: :edit_eval, edit_form: form)}
  end

  defp open_sheet(socket, :course),
    do:
      {:noreply,
       assign(socket, sheet: :course, course_query: "", course_units: course_units(socket))}

  defp open_sheet(socket, sheet), do: {:noreply, assign(socket, :sheet, sheet)}

  # The rename / new maximum of the selected column, checked before any write.
  defp edit_attrs(p, socket) do
    %{column: column, columns: columns} = socket.assigns
    label = String.trim(p["label"] || "")

    cond do
      label == "" ->
        {:error, gettext("Donnez un nom à l'évaluation.")}

      Enum.any?(columns, &(&1.id != column.id and &1.label == label)) ->
        {:error, gettext("Une autre évaluation de la séquence porte déjà ce nom.")}

      true ->
        case Curriculum.parse_coefficient(p["max_score"] || "") do
          {:ok, max} -> {:ok, %{label: label, max_score: max}}
          :error -> {:error, gettext("Le barème doit être un nombre positif (ex. 20).")}
        end
    end
  end

  defp update_column(socket, attrs) do
    %{current_scope: scope, column: column, seq: seq} = socket.assigns

    case Assessment.update_assessments(scope, column_assessments(column), attrs) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Évaluation modifiée."))
         |> push_patch(to: marks_path(socket, seq, column.id))}

      {:error, :marks_above_max} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Des notes déjà saisies dépassent ce barème : corrigez-les d'abord.")
         )}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}
    end
  end

  # One row per course of the teacher (the picker): its classes, its séquence entry
  # progress (`EntryProgress.context_cells/4`) and its evaluation count.
  defp course_units(socket) do
    %{current_scope: scope, ctx: ctx, seq: seq} = socket.assigns

    units =
      for unit <- Curriculum.list_units_for_scope(scope) do
        case unit do
          {:course, course} -> {unit, Curriculum.contexts_of_course!(course.id, scope: scope)}
          {:solo, tc} -> {unit, [tc]}
        end
      end

    contexts =
      units
      |> Enum.flat_map(&elem(&1, 1))
      |> Ash.load!([class_group: [:enrollment_count]], scope: scope)
      |> Enum.reject(&is_nil(&1.class_group))

    by_id = Map.new(contexts, &{&1.id, &1})
    cells = unit_cells(scope, seq, contexts)

    Enum.flat_map(units, fn {unit, members} ->
      case members |> Enum.map(&by_id[&1.id]) |> Enum.reject(&is_nil/1) do
        [] -> []
        members -> [unit_row(unit, Enum.sort_by(members, &sort_label/1), cells, ctx)]
      end
    end)
  end

  defp sort_label(tc), do: String.downcase(tc.class_group.label)

  defp unit_cells(_scope, nil, _contexts), do: %{}

  defp unit_cells(scope, seq, contexts),
    do: EntryProgress.context_cells(scope, scope.current_academic_year, seq, contexts)

  defp unit_row(unit, [first | _] = members, cells, ctx) do
    figures =
      Enum.map(members, &Map.get(cells, &1.id, %{entered: 0, expected: 0, assessments: 0}))

    %{
      id: first.id,
      label: Curriculum.unit_label(unit),
      context_id: first.id,
      classes: classes_line(unit, members),
      entered: figures |> Enum.map(& &1.entered) |> Enum.sum(),
      expected: figures |> Enum.map(& &1.expected) |> Enum.sum(),
      assessments: figures |> Enum.map(& &1.assessments) |> Enum.max(fn -> 0 end),
      current?: current_unit?(unit, ctx)
    }
  end

  defp classes_line({:course, _}, members),
    do: Enum.map_join(members, " · ", & &1.class_group.label)

  defp classes_line({:solo, _}, [tc]),
    do: ngettext("%{count} élève", "%{count} élèves", tc.class_group.enrollment_count || 0)

  defp matches_query?(_unit, ""), do: true

  defp matches_query?(unit, query) do
    haystack = String.downcase(unit.label <> " " <> unit.classes)
    String.contains?(haystack, String.downcase(String.trim(query)))
  end

  # --- Saving a mark -----------------------------------------------------------------

  defp save_entry(%{assigns: %{upcoming?: true}} = socket, _id, _raw),
    do: put_flash(socket, :error, not_open_message())

  defp save_entry(%{assigns: %{locked?: true}} = socket, _id, _raw),
    do: put_flash(socket, :error, gettext("Séquence verrouillée."))

  defp save_entry(socket, id, raw) do
    socket = assign(socket, :scores, Map.put(socket.assigns.scores, id, raw))

    case MarkEntry.parse(raw) do
      :error -> put_error(socket, id, :invalid)
      {:ok, entry} -> write_mark(socket, id, entry)
    end
  end

  # Writes one student's mark to their own class's assessment — only when it differs
  # from what this page loaded, so a blur never rewrites (nor overwrites another
  # device's newer value of) an untouched mark.
  defp write_mark(socket, id, entry) do
    %{current_scope: scope, loaded: loaded} = socket.assigns

    cond do
      not Map.has_key?(socket.assigns.student_group, id) ->
        socket

      same_entry?(entry, MarkEntry.parse(Map.get(loaded, id))) ->
        socket
        |> clear_error(id)
        |> assign(:scores, Map.put(socket.assigns.scores, id, Map.get(loaded, id, "")))

      not TeacherAssistant.Scope.school_verified?(scope) ->
        put_flash(
          socket,
          :error,
          gettext("École en attente de vérification — enregistrement indisponible.")
        )

      true ->
        case assessment_for(socket.assigns, id) do
          nil -> put_error(socket, id, :no_assessment)
          assessment -> upsert(socket, assessment, id, entry)
        end
    end
  end

  defp upsert(socket, assessment, id, entry) do
    attrs = Map.put(entry_attrs(entry), :student_id, id)

    case Assessment.upsert_marks(socket.assigns.current_scope, assessment, [attrs]) do
      :ok ->
        text = mark_text(entry)

        socket
        |> clear_error(id)
        |> assign(:saved_at, Reference.now())
        |> assign(:loaded, Map.put(socket.assigns.loaded, id, text))
        |> assign(:scores, Map.put(socket.assigns.scores, id, text))
        |> assign_pending()

      {:error, :out_of_range} ->
        put_error(socket, id, :out_of_range)

      {:error, %Ash.Error.Forbidden{}} ->
        Authz.put_not_allowed(socket)

      _ ->
        failed(socket, id)
    end
  end

  # A refused write on a séquence that has locked since the page loaded: show the page
  # as locked (banner and correction link) instead of a bare per-cell failure.
  defp failed(%{assigns: %{seq: %{id: seq_id}}} = socket, id) do
    case Lock.fetch_sequence(seq_id, socket.assigns.current_scope) do
      {:ok, seq} ->
        if Lock.locked?(seq) do
          socket
          |> assign(seq: seq, locked?: true, errors: %{}, scores: socket.assigns.loaded)
          |> put_flash(:error, gettext("Séquence verrouillée."))
        else
          put_error(socket, id, :failed)
        end

      _ ->
        put_error(socket, id, :failed)
    end
  end

  defp failed(socket, id), do: put_error(socket, id, :failed)

  defp assessment_for(%{course: %CombinedCourse{}, column: column, student_group: groups}, id),
    do: column && column.by_class_group_id[groups[id]]

  defp assessment_for(%{column: column}, _id), do: column

  defp put_error(socket, id, :failed),
    do: assign(socket, :errors, Map.put(socket.assigns.errors, id, gettext("Non enregistrée")))

  defp put_error(socket, id, :no_assessment) do
    message = gettext("Non enregistrée : cette évaluation manque pour sa classe")
    assign(socket, :errors, Map.put(socket.assigns.errors, id, message))
  end

  defp put_error(socket, id, _invalid_or_out_of_range) do
    message =
      gettext("Note entre 0 et %{max}", max: MarksComponents.max_text(socket.assigns.column))

    assign(socket, :errors, Map.put(socket.assigns.errors, id, message))
  end

  defp clear_error(socket, id), do: assign(socket, :errors, Map.delete(socket.assigns.errors, id))

  # The field text a stored entry shows, as `mark_field/1` renders a stored mark.
  defp mark_text(:blank), do: ""
  defp mark_text({:graded, d}), do: MarkEntry.format(:graded, d)
  defp mark_text(status), do: MarkEntry.format(status, nil)

  defp same_entry?({:graded, a}, {:ok, {:graded, b}}), do: Decimal.equal?(a, b)
  defp same_entry?(entry, {:ok, entry}), do: true
  defp same_entry?(_entry, _loaded), do: false

  # Upsert-entry attributes for a parsed mark (a blank is "not entered": nil score).
  defp entry_attrs(:blank), do: %{score: nil}
  defp entry_attrs({:graded, d}), do: %{score: d}
  defp entry_attrs(status) when status in [:absent, :excused], do: %{score: nil, status: status}

  # A mark map for the provisional average.
  defp entry_mark({:graded, d}), do: %{score: d, status: :graded}
  defp entry_mark(status), do: %{score: nil, status: status}

  defp save_competence(%{assigns: %{seq: %{} = seq, ctx: ctx}} = socket, text) do
    case Assessment.put_sequence_competence(socket.assigns.current_scope, ctx, seq, text) do
      :ok ->
        {:noreply, socket |> load_competence() |> assign(saved_at: Reference.now(), sheet: nil)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Compétence non enregistrée."))}
    end
  end

  defp save_competence(socket, _text), do: {:noreply, socket}

  # --- Render ------------------------------------------------------------------------

  def render(%{loading?: true} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["courses"]}
    >
      <.page_header title={@page_title} />
      <.loading_panel id="marks-loading" />
    </Layouts.app>
    """
  end

  def render(assigns) do
    students = all_students(assigns)
    done = if assigns.column, do: entered_count(students, assigns.loaded), else: 0

    average =
      assigns.column &&
        preview_average(students, assigns.column, assigns.loaded, assigns.grading_rules)

    assigns =
      assign(assigns,
        students: students,
        total: length(students),
        done: done,
        missing: length(students) - done,
        average: average,
        next_empty: next_empty_id(assigns),
        can_create?: assigns.seq != nil and not assigns.locked?,
        editable?: assigns.column != nil and (not assigns.locked? or assigns.upcoming?),
        deletable?:
          assigns.column != nil and (not assigns.locked? or assigns.upcoming?) and
            no_marks?(assigns.loaded)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["courses"]}
      immersive
    >
      <section id="teacher-marks" class={["space-y-4", @column && "pb-44 sm:pb-0"]}>
        <%!-- Phones: the task header. Its title opens the course picker. --%>
        <header id="marks-phone-header" class="-mt-1 flex items-center gap-1.5 sm:hidden">
          <.link
            id="marks-back"
            navigate={~p"/school/courses"}
            aria-label={gettext("Retour à Mes cours")}
            class="btn btn-ghost btn-square -ml-2 shrink-0"
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <button
            type="button"
            id="course-picker-open"
            phx-click={JS.push("open_sheet", value: %{sheet: "course"})}
            class="flex min-w-0 flex-1 flex-col items-start text-left"
          >
            <%!-- two lines rather than cut: on a narrow phone the class would be lost --%>
            <span class="flex max-w-full items-center gap-1 font-semibold leading-tight">
              <span id="marks-phone-title" class="line-clamp-2">{@title}</span>
              <.icon name="hero-chevron-down" class="size-3.5 shrink-0" />
            </span>
            <span class="max-w-full truncate text-xs text-base-content/70">
              {course_subtitle(@course, @groups, @total)}
            </span>
          </button>
          <button
            :if={@seq}
            type="button"
            id="seq-picker-open"
            phx-click={JS.push("open_sheet", value: %{sheet: "seq"})}
            class="btn btn-sm btn-outline shrink-0 gap-1 rounded-full border-base-300"
          >
            {gettext("Séq. %{n}", n: @seq.number)}<span
              :if={!@locked? && Dates.countdown(@seq.grade_entry_deadline, @today)}
              class="ta-num hidden font-normal text-warning min-[400px]:inline"
            >· {Dates.countdown(@seq.grade_entry_deadline, @today)}</span>
            <.icon name="hero-chevron-down" class="size-3.5" />
          </button>
        </header>

        <%!-- From sm: the course and its classes in the breadcrumb, séquence tabs, deadline. --%>
        <header id="marks-header" class="hidden flex-wrap items-end gap-x-4 gap-y-3 sm:flex">
          <div class="min-w-0 flex-[1_1_20rem] space-y-1">
            <.breadcrumb>
              <:crumb id="teaching-nav-back" navigate={~p"/school/courses"}>
                {gettext("Mes cours")}
              </:crumb>
              <:crumb>
                <button
                  type="button"
                  id="course-picker-open-desktop"
                  phx-click={JS.push("open_sheet", value: %{sheet: "course"})}
                  class="link link-hover font-semibold text-primary"
                >
                  {@title}
                </button>
                <span :if={@course}>· {Enum.map_join(@groups, ", ", & &1.class_group.label)}</span>
              </:crumb>
            </.breadcrumb>
            <h1 class="text-2xl font-semibold leading-tight">{gettext("Saisie des notes")}</h1>
          </div>
          <div
            :if={@sequences != []}
            id="seq-tabs"
            role="tablist"
            aria-label={gettext("Séquence")}
            phx-hook="ScrollActiveTab"
            class="flex max-w-full gap-1 overflow-x-auto rounded-box border border-base-300 p-1"
          >
            <.link
              :for={s <- @sequences}
              id={"seq-tab-#{s.id}"}
              patch={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{s.id}"}
              aria-current={@seq && @seq.id == s.id && "page"}
              class={[
                "whitespace-nowrap rounded-[0.5rem] px-3 py-1.5 text-sm transition-colors",
                if(@seq && @seq.id == s.id,
                  do: "bg-base-content font-semibold text-base-100",
                  else: "text-base-content/70 hover:bg-base-200"
                )
              ]}
            >
              {seq_tab_label(s, @today)}
            </.link>
          </div>
          <span
            :if={@seq && !@locked?}
            id="deadline-chip"
            class="ta-num inline-flex h-8 items-center rounded-full bg-warning/15 px-3 text-xs font-semibold text-warning"
          >
            {deadline_text(@seq, @today)}
          </span>
        </header>

        <.teaching_nav context_id={@ctx.id} label={@title} current={:marks} crumbs={false} />

        <.locked_banner :if={@locked? and !@upcoming?} seq={@seq} assessment={@column} />
        <.upcoming_banner :if={@upcoming?} seq={@seq} />

        <%!-- Evaluations: chips on phones, cards from sm. --%>
        <nav
          :if={@seq && (@columns != [] or @can_create?)}
          id="eval-chips"
          aria-label={gettext("Évaluations")}
          class="-mx-4 flex gap-2 overflow-x-auto px-4 pb-0.5 sm:hidden"
        >
          <MarksComponents.eval_chip
            :for={c <- @columns}
            id={"eval-chip-#{c.id}"}
            column={c}
            count={column_count(c, assigns)}
            total={@total}
            current?={@column && c.id == @column.id}
            patch={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{@seq.id}&assessment=#{c.id}"}
          />
          <button
            :if={@can_create?}
            type="button"
            id="new-eval-chip"
            phx-click={JS.push("open_sheet", value: %{sheet: "new_eval"})}
            class="flex h-12 flex-none items-center gap-1.5 rounded-[0.625rem] border border-dashed border-base-content/30 px-3.5 text-[0.8rem] font-semibold text-base-content/70 transition-colors hover:border-primary hover:text-primary"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("Nouvelle")}
          </button>
        </nav>
        <nav
          :if={@seq && (@columns != [] or @can_create?)}
          id="eval-cards"
          aria-label={gettext("Évaluations")}
          class="hidden flex-wrap items-stretch gap-2 sm:flex"
        >
          <MarksComponents.eval_chip
            :for={c <- @columns}
            id={"eval-card-#{c.id}"}
            variant={:card}
            column={c}
            count={column_count(c, assigns)}
            total={@total}
            current?={@column && c.id == @column.id}
            patch={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{@seq.id}&assessment=#{c.id}"}
          />
          <button
            :if={@can_create?}
            type="button"
            id="new-eval-card"
            phx-click={JS.push("open_sheet", value: %{sheet: "new_eval"})}
            class="flex items-center gap-1.5 rounded-box border border-dashed border-base-content/30 px-4 py-3 text-sm font-semibold text-base-content/70 transition-colors hover:border-primary hover:text-primary"
          >
            <.icon name="hero-plus" class="size-4" />{gettext("Nouvelle évaluation")}
          </button>
        </nav>

        <%!-- Combined course, phones: jump to a class. --%>
        <nav
          :if={@course && @column && length(@groups) > 1}
          id="class-chips"
          aria-label={gettext("Aller à une classe")}
          class="-mx-4 flex gap-1.5 overflow-x-auto border-y border-base-300 px-4 py-2.5 sm:hidden"
        >
          <a
            :for={g <- @groups}
            id={"class-chip-#{g.class_group.id}"}
            href={"#marks-class-#{g.class_group.id}"}
            class={[
              "flex h-[2.125rem] flex-none items-center gap-1 rounded-full px-3 text-xs font-semibold",
              if(next_in_group?(g, @next_empty),
                do: "bg-base-content text-base-100",
                else: "border border-base-content/20"
              )
            ]}
          >
            {g.class_group.label}
            <span class="ta-num font-medium opacity-85">
              {entered_count(g.students, @loaded)}/{length(g.students)}
            </span>
          </a>
        </nav>

        <div
          :if={@column || (@apc? && @seq)}
          id="marks-toolbar"
          class={
            [
              "flex flex-wrap items-center gap-x-3 gap-y-2",
              # Without a competence line the box would frame a lone menu.
              @apc? && @seq &&
                "sm:rounded-box sm:border sm:border-base-300 sm:bg-base-100 sm:px-3.5 sm:py-2.5"
            ]
          }
        >
          <%!-- Phones: one line, the full form in a sheet; while it is missing (and
               can still be written), a banner the teacher cannot overlook. --%>
          <button
            :if={@apc? && @seq && is_nil(@competence) && !@locked?}
            type="button"
            id="competence-open"
            phx-click={JS.push("open_sheet", value: %{sheet: "competence"})}
            class="flex w-full items-center gap-3 rounded-box border border-warning/50 bg-warning/10 px-3 py-2.5 text-left sm:hidden"
          >
            <.icon name="hero-pencil-square" class="size-5 shrink-0 text-warning" />
            <span class="min-w-0 flex-1">
              <span class="block text-sm font-semibold">
                {gettext("Compétence de la séquence %{n} à écrire", n: @seq.number)}
              </span>
              <span class="block text-xs text-base-content/70">
                {gettext("Elle figure sur le bulletin de chaque élève.")}
              </span>
            </span>
            <span class="btn btn-sm btn-warning shrink-0">{gettext("Écrire")}</span>
          </button>
          <button
            :if={@apc? && @seq && !(is_nil(@competence) && !@locked?)}
            type="button"
            id="competence-open"
            phx-click={JS.push("open_sheet", value: %{sheet: "competence"})}
            class={[
              "min-w-0 flex-1 truncate text-left text-xs sm:hidden",
              if(@competence, do: "text-base-content/70", else: "font-semibold text-warning")
            ]}
          >
            {if @competence,
              do: gettext("Compétence : %{text}", text: @competence),
              else: gettext("Compétence à renseigner — elle figure sur le bulletin")}
          </button>
          <%!-- pushes the evaluation menu to the right, under the banner --%>
          <span
            :if={!(@apc? && @seq) or (is_nil(@competence) && !@locked?)}
            class="flex-1 sm:hidden"
          ></span>
          <.competence_form
            :if={@apc? && @seq}
            id="sequence-competence"
            seq={@seq}
            text={@competence}
            locked?={@locked?}
            class="hidden min-w-0 flex-[1_1_18rem] sm:flex"
            inline
          />
          <span :if={!(@apc? && @seq)} class="hidden flex-1 sm:block"></span>
          <MarksComponents.save_indicator
            id="save-state"
            errors={@errors}
            saved_at={@saved_at}
            variant={:inline}
          />
          <.action_menu
            :if={@editable? or @deletable?}
            id="eval-menu"
            trigger_label={@column.label}
            label={gettext("Options de l'évaluation")}
          >
            <:item
              :if={@editable?}
              id="eval-edit"
              icon="hero-pencil-square"
              click={JS.push("open_sheet", value: %{sheet: "edit_eval"})}
            >
              {gettext("Renommer ou changer le barème")}
            </:item>
            <:item
              :if={@deletable?}
              id="delete-assessment"
              icon="hero-trash"
              click="delete_assessment"
              confirm={delete_confirm(@column, @course != nil)}
              danger
            >
              {gettext("Supprimer")}
            </:item>
          </.action_menu>
        </div>
        <div
          :if={@apc? && @seq && is_nil(@competence) && !@competence_reminder_dismissed? && !@locked?}
          id="competence-reminder"
          role="status"
          class="hidden items-start justify-between gap-3 rounded-box border border-warning/40 bg-warning/10 px-3 py-2 text-sm sm:flex"
        >
          <span>{gettext("Écrivez la compétence évaluée — elle figure sur le bulletin")}</span>
          <button
            type="button"
            phx-click="dismiss_competence_reminder"
            class="cursor-pointer text-base-content/70 transition-colors hover:text-base-content"
            aria-label={gettext("Fermer")}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div :if={@seq && @columns == []} id="marks-empty">
          <.empty_state
            icon="hero-pencil-square"
            title={gettext("Aucune évaluation pour la séquence %{n}", n: @seq.number)}
            message={empty_message(@upcoming?, @locked?)}
          >
            <:action :if={@can_create?}>
              <button
                type="button"
                id="new-eval-empty"
                phx-click={JS.push("open_sheet", value: %{sheet: "new_eval"})}
                class="btn btn-primary btn-sm"
              >
                <.icon name="hero-plus" class="size-4" />{gettext("Nouvelle évaluation")}
              </button>
            </:action>
          </.empty_state>
        </div>

        <div
          :if={@column}
          class="grid grid-cols-[minmax(0,1fr)] items-start gap-4 lg:grid-cols-[minmax(0,1fr)_17rem]"
        >
          <div class="space-y-3">
            <.pending_makeups names={@pending_makeups} />
            <div class="-mx-4 border-y border-base-300 bg-base-100 sm:mx-0 sm:overflow-x-auto sm:rounded-box sm:border">
              <%!-- `max-sm:block`, not `block sm:table`: daisyUI's `table` class is also
                   Tailwind's `display: table` utility, which comes after `.block` and
                   would keep a real table on phones, as wide as its longest name --%>
              <table id="marks-table" class="table table-sm max-sm:block" phx-hook=".MarksGrid">
                <thead class="hidden sm:table-header-group">
                  <tr>
                    <th>{gettext("N°")}</th>
                    <th>{gettext("Élève")}</th>
                    <th class="whitespace-nowrap">
                      {@column.label} · /{MarksComponents.max_text(@column)}
                    </th>
                    <th><span class="sr-only">{gettext("État")}</span></th>
                    <th>{gettext("Appréciation")}</th>
                    <th><span class="sr-only">{gettext("Actions")}</span></th>
                  </tr>
                </thead>
                <tbody
                  :for={group <- @groups}
                  id={"marks-class-#{group.class_group.id}"}
                  class="block scroll-mt-2 sm:table-row-group"
                >
                  <tr
                    :if={@course}
                    class="sticky top-0 z-10 flex border-b border-base-300 bg-base-200 sm:static sm:table-row"
                  >
                    <th colspan="6" class="ta-eyebrow flex-1 px-4 py-2 sm:bg-base-200/60">
                      <span class="flex items-center justify-between gap-3">
                        <span>
                          {group.class_group.label} · {ngettext(
                            "%{count} élève",
                            "%{count} élèves",
                            length(group.students)
                          )}
                        </span>
                        <span class="ta-num font-medium">
                          {entered_count(group.students, @loaded)}/{length(group.students)}
                        </span>
                      </span>
                    </th>
                  </tr>
                  <MarksComponents.mark_row
                    :for={{s, i} <- Enum.with_index(group.students, 1)}
                    student={s}
                    n={i}
                    value={Map.get(@scores, s.id, "")}
                    saved={Map.get(@loaded, s.id, "")}
                    error={@errors[s.id]}
                    locked?={@locked?}
                    next?={s.id == @next_empty}
                    max={@column.max_score}
                    grading_rules={@grading_rules}
                  />
                </tbody>
              </table>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".MarksGrid">
                // Enter / ↓ move to the next student's box, ↑ to the previous (the blur
                // saves this one). On phones a box opens the keypad instead of the
                // system keyboard (`inputmode="none"`, kept by `JS.ignore_attributes`).
                const PHONE = "(max-width: 639.98px)"
                export default {
                  mounted() {
                    this.phone = window.matchMedia(PHONE)
                    this.applyMode = () => {
                      const mode = this.phone.matches ? "none" : "decimal"
                      this.el.querySelectorAll("input[data-mark-input]").forEach((i) => i.setAttribute("inputmode", mode))
                    }
                    this.applyMode()
                    this.phone.addEventListener("change", this.applyMode)
                    this.el.addEventListener("click", (e) => {
                      const input = e.target.closest("input[data-mark-input]")
                      if (!input || input.disabled || !this.phone.matches) return
                      e.preventDefault()
                      input.blur()
                      this.pushEvent("keypad_open", {student: input.dataset.student})
                    })
                    this.el.addEventListener("keydown", (e) => {
                      const input = e.target.closest("input[data-mark-input]")
                      if (!input) return
                      const step = e.key === "Enter" || e.key === "ArrowDown" ? 1 : e.key === "ArrowUp" ? -1 : 0
                      if (step === 0) return
                      e.preventDefault()
                      const inputs = [...this.el.querySelectorAll("input[data-mark-input]:not([disabled])")]
                      const target = inputs[inputs.indexOf(input) + step]
                      if (target) { target.focus(); target.select() } else if (step > 0) input.blur()
                    })
                  },
                  updated() { this.applyMode() },
                  destroyed() { this.phone && this.phone.removeEventListener("change", this.applyMode) }
                }
              </script>
            </div>
          </div>

          <aside class="hidden space-y-3 sm:block lg:sticky lg:top-4">
            <MarksComponents.side_panel
              title={side_title(@column, @groups, @course, @seq)}
              done={@done}
              total={@total}
              average={fmt_avg(@average)}
              average_low?={low_avg?(@average)}
              missing={missing_line(@missing, @seq, @locked?)}
              saved_at={@saved_at}
              to_fix={to_fix(@errors, @students)}
              next_empty={@next_empty}
            />
            <div id="marks-shortcuts" class="ta-leaf space-y-1.5 text-sm">
              <p class="ta-eyebrow">{gettext("Raccourcis")}</p>
              <p>
                <kbd class="kbd kbd-sm">{gettext("Entrée")}</kbd>
                / <kbd class="kbd kbd-sm">↓</kbd> {gettext("élève suivant")} ·
                <kbd class="kbd kbd-sm">↑</kbd> {gettext("précédent")}
              </p>
              <p>
                <kbd class="kbd kbd-sm">a</kbd> {gettext("absent")} ·
                <kbd class="kbd kbd-sm">abj</kbd> {gettext("absence justifiée")}
              </p>
              <p class="text-base-content/70">{gettext("12,5 ou 12.5")}</p>
              <p class="text-base-content/70">
                {gettext("Chaque note est enregistrée dès que vous quittez la case.")}
              </p>
            </div>
          </aside>
        </div>

        <%!-- Phones: what is left, the provisional average and the keypad. --%>
        <div
          :if={@column}
          id="marks-bottom-bar"
          class="fixed inset-x-0 bottom-0 z-20 flex flex-col gap-2.5 border-t border-base-300 bg-base-200/95 px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3 backdrop-blur sm:hidden"
        >
          <div class="ta-num flex items-baseline gap-3">
            <span id="bottom-progress" class="text-xl font-semibold">
              {@done}<span class="text-[0.8rem] font-normal text-base-content/70">/{gettext(
                "%{total} saisies",
                total: @total
              )}</span>
            </span>
            <span class="flex-1"></span>
            <span id="bottom-average" class="text-xs text-base-content/70">
              {gettext("Moy. prov.")}
              <span class={[
                "font-semibold",
                if(low_avg?(@average), do: "text-error", else: "text-primary")
              ]}>
                {fmt_avg(@average)}
              </span>
            </span>
          </div>
          <div class="h-1 overflow-hidden rounded-full bg-base-300" aria-hidden="true">
            <div
              class={[
                "h-full rounded-full transition-[width] duration-500",
                if(@missing == 0, do: "bg-primary", else: "bg-warning")
              ]}
              style={"width: #{if @total > 0, do: div(@done * 100, @total), else: 0}%"}
            >
            </div>
          </div>
          <button
            :if={!@locked? && @missing > 0}
            type="button"
            id="keypad-open"
            phx-click="keypad_open"
            class="btn btn-primary h-12 w-full text-[0.95rem]"
          >
            {ngettext(
              "Saisir la note manquante",
              "Saisir les %{count} notes manquantes",
              @missing
            )}
            <.icon name="hero-arrow-right" class="size-4" />
          </button>
        </div>
      </section>

      <MarksComponents.keypad
        :if={@keypad && @column}
        {keypad_assigns(assigns)}
        column={@column}
        course_title={if @course, do: @course.label, else: @ctx.subject}
        scores={@scores}
        errors={@errors}
        done={@done}
        total={@total}
        saved_at={@saved_at}
        grading_rules={@grading_rules}
      />

      <.drawer
        :if={@sheet == :course}
        id="course-sheet"
        title={gettext("Saisir les notes de…")}
        on_close={JS.push("close_sheet")}
      >
        <form id="course-search" phx-change="course_search" phx-submit="course_search">
          <label class="input w-full">
            <.icon name="hero-magnifying-glass" class="size-4 text-base-content/70" />
            <span class="sr-only">{gettext("Rechercher un cours")}</span>
            <input
              type="search"
              name="q"
              value={@course_query}
              placeholder={gettext("Classe ou cours (ex. 6ème)")}
              phx-debounce="150"
              autocomplete="off"
              class="grow"
            />
          </label>
        </form>
        <div id="course-options" class="-mx-5 flex flex-col">
          <.list_row
            :for={u <- Enum.filter(@course_units, &matches_query?(&1, @course_query))}
            id={"course-option-#{u.id}"}
            navigate={~p"/teacher/contexts/#{u.context_id}/marks?#{seq_query(@seq)}"}
            title={u.label}
            meta={u.classes}
            selected={u.current?}
          >
            <:trailing>
              <span class="ta-num text-xs font-semibold text-warning">
                {if u.assessments == 0,
                  do: gettext("0 éval."),
                  else: "#{u.entered}/#{u.expected}"}
              </span>
            </:trailing>
          </.list_row>
        </div>
      </.drawer>

      <.drawer
        :if={@sheet == :seq}
        id="seq-sheet"
        title={gettext("Séquence")}
        on_close={JS.push("close_sheet")}
      >
        <div class="-mx-5 flex flex-col">
          <.list_row
            :for={s <- @sequences}
            id={"seq-option-#{s.id}"}
            patch={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{s.id}"}
            title={gettext("Séquence %{n}", n: s.number)}
            meta={seq_state_line(s, @today)}
            selected={@seq && @seq.id == s.id}
          />
        </div>
      </.drawer>

      <.drawer
        :if={@sheet == :competence && @seq}
        id="competence-sheet"
        eyebrow={@title}
        title={gettext("Compétence évaluée")}
        on_close={JS.push("close_sheet")}
      >
        <p class="text-sm text-base-content/70">
          {gettext("Elle figure sur le bulletin, une par séquence.")}
        </p>
        <.competence_form
          id="sequence-competence-sheet"
          seq={@seq}
          text={@competence}
          locked?={@locked?}
        />
      </.drawer>

      <.drawer
        :if={@sheet == :new_eval && @seq}
        id="new-eval-sheet"
        eyebrow={"#{@title} · #{gettext("Séquence %{n}", n: @seq.number)}"}
        title={gettext("Nouvelle évaluation")}
        on_close={JS.push("close_sheet")}
      >
        <.form
          for={@new_assessment_form}
          id="new-assessment-form"
          phx-change="new_eval_change"
          phx-submit="new_assessment"
          class="space-y-5"
        >
          <fieldset :if={@assessment_types != []}>
            <legend class="mb-2.5 text-sm text-base-content/70">{gettext("Type")}</legend>
            <div class="flex flex-wrap gap-2">
              <.chip_radio
                :for={t <- @assessment_types}
                id={"new-eval-type-#{t.id}"}
                name="assessment[assessment_type_id]"
                value={t.id}
                checked={@new_assessment_form.params["assessment_type_id"] == t.id}
              >
                {t.name}
              </.chip_radio>
            </div>
          </fieldset>
          <div class="grid grid-cols-[minmax(0,1fr)_6rem] items-start gap-3">
            <.input
              field={@new_assessment_form[:label]}
              label={gettext("Nom")}
              placeholder={gettext("ex. Devoir 1")}
            />
            <.input
              type="text"
              id="new-eval-max"
              inputmode="decimal"
              name="assessment[max_score]"
              label={gettext("Noté sur")}
              value={
                @new_assessment_form.params["max_score"] || Decimal.to_string(@default_max, :normal)
              }
              class="ta-num input w-full text-center"
            />
          </div>
          <p class="-mt-3 text-xs text-base-content/70">
            {gettext("Le nom se remplit d'après le type ; modifiable.")}
          </p>
          <%!-- APC: one competence per séquence, so asked only while it has none --%>
          <div :if={@apc? && is_nil(@competence)} id="new-eval-competence-field">
            <.input
              type="text"
              id="new-eval-competence"
              name="competence[text]"
              value={@new_competence}
              maxlength="140"
              label={gettext("Compétence évaluée (séquence %{n})", n: @seq.number)}
              placeholder={gettext("ex. Résoudre une équation")}
            />
            <p class="mt-1 text-xs text-base-content/70">
              {gettext(
                "Une par séquence pour la matière ; elle figure sur le bulletin. Vous pouvez aussi l'écrire plus tard."
              )}
            </p>
          </div>
          <button type="submit" id="new-eval-submit" class="btn btn-primary h-12 w-full">
            {gettext("Créer et commencer la saisie")}
          </button>
        </.form>
      </.drawer>

      <.drawer
        :if={@sheet == :edit_eval && @column && @edit_form}
        id="edit-eval-sheet"
        eyebrow={@title}
        title={gettext("Modifier l'évaluation")}
        on_close={JS.push("close_sheet")}
      >
        <.form
          for={@edit_form}
          id="edit-assessment-form"
          phx-submit="edit_assessment"
          class="space-y-5"
        >
          <div class="grid grid-cols-[minmax(0,1fr)_6rem] items-start gap-3">
            <.input field={@edit_form[:label]} label={gettext("Nom")} />
            <.input
              field={@edit_form[:max_score]}
              inputmode="decimal"
              label={gettext("Noté sur")}
              class="ta-num input w-full text-center"
            />
          </div>
          <p :if={@course} class="-mt-3 text-xs text-base-content/70">
            {gettext("Le changement vaut pour toutes les classes du cours.")}
          </p>
          <button type="submit" id="edit-eval-submit" class="btn btn-primary w-full">
            {gettext("Enregistrer")}
          </button>
        </.form>
      </.drawer>
    </Layouts.app>
    """
  end

  # The keypad's focus: the student, the two before (dimmed), the next few (as many
  # as a tall phone shows; the keypad clips the rest), and how many boxes are still
  # empty in their class.
  defp keypad_assigns(%{keypad: id, roster: roster, loaded: loaded}) do
    index = Enum.find_index(roster, &(&1.student.id == id)) || 0
    focus = Enum.at(roster, index)

    remaining =
      Enum.count(
        roster,
        &(&1.class_group.id == focus.class_group.id and blank?(loaded, &1.student.id))
      )

    %{
      focus: focus,
      prev_rows: Enum.slice(roster, max(index - 2, 0), min(index, 2)),
      next_rows: Enum.slice(roster, index + 1, 8),
      remaining: remaining
    }
  end

  defp column_count(%{id: id}, %{column: %{id: id}, done: done}), do: done

  defp column_count(column, %{column_marks: marks}),
    do: marks |> Map.get(column.id, MapSet.new()) |> MapSet.size()

  defp next_in_group?(_group, nil), do: false
  defp next_in_group?(group, id), do: Enum.any?(group.students, &(&1.id == id))

  defp to_fix(errors, students),
    do: for(s <- students, Map.has_key?(errors, s.id), do: s.full_name)

  defp course_subtitle(nil, _groups, total),
    do: ngettext("%{count} élève", "%{count} élèves", total)

  defp course_subtitle(_course, groups, total) do
    gettext("Cours groupé") <>
      " · " <>
      ngettext("%{count} classe", "%{count} classes", length(groups)) <>
      " · " <> ngettext("%{count} élève", "%{count} élèves", total)
  end

  # « Clôture 8 nov. · J-5 »
  defp deadline_text(seq, today) do
    case Dates.countdown(seq.grade_entry_deadline, today) do
      nil ->
        gettext("Clôture %{date}", date: Dates.day_month(seq.grade_entry_deadline))

      left ->
        gettext("Clôture %{date} · %{left}",
          date: Dates.day_month(seq.grade_entry_deadline),
          left: left
        )
    end
  end

  attr :id, :string, required: true
  attr :seq, :map, required: true
  attr :text, :string, default: nil
  attr :locked?, :boolean, default: false
  attr :inline, :boolean, default: false, doc: "the desktop toolbar: label, field, saved on blur"
  attr :class, :any, default: nil

  # Spec bulletin v2 §6: the competence printed on the APC report card, one per séquence.
  defp competence_form(assigns) do
    ~H"""
    <.form
      for={to_form(%{"text" => @text}, as: :competence)}
      id={@id}
      phx-submit="save_competence"
      class={[
        if(@inline, do: "items-center gap-2.5", else: "flex flex-col gap-3"),
        @class
      ]}
    >
      <label
        :if={@inline}
        for={"#{@id}-text"}
        class="shrink-0 text-sm text-base-content/70"
      >
        {gettext("Compétence évaluée")}
      </label>
      <input
        :if={@inline}
        type="text"
        id={"#{@id}-text"}
        name="competence[text]"
        value={@text}
        maxlength="140"
        disabled={@locked?}
        placeholder={gettext("À renseigner — figure sur le bulletin")}
        phx-blur="save_competence_blur"
        class={["input input-sm min-w-0 flex-1", is_nil(@text) && "border-warning/60"]}
      />
      <.input
        :if={!@inline}
        name="competence[text]"
        id={"#{@id}-text"}
        value={@text}
        label={gettext("Compétence évaluée (séquence %{n})", n: @seq.number)}
        maxlength="140"
        disabled={@locked?}
      />
      <button :if={!@inline and !@locked?} type="submit" class="btn btn-primary w-full">
        {gettext("Enregistrer")}
      </button>
    </.form>
    """
  end

  defp seq_query(nil), do: []
  defp seq_query(seq), do: [seq: seq.id]

  # « Séquence 2 · ouverte » / « · verrouillée » / « · à venir ».
  defp seq_tab_label(seq, today) do
    base = gettext("Séquence %{n}", n: seq.number)

    cond do
      Lock.locked?(seq, today) -> base <> " · " <> gettext("verrouillée")
      Lock.not_started?(seq, today) -> base <> " · " <> gettext("à venir")
      true -> base <> " · " <> gettext("ouverte")
    end
  end

  # The séquence sheet's line under each séquence.
  defp seq_state_line(seq, today) do
    cond do
      Lock.locked?(seq, today) ->
        gettext("Verrouillée")

      Lock.not_started?(seq, today) ->
        gettext("À venir · la saisie ouvre le %{date}", date: Dates.day_month(seq.start_date))

      true ->
        gettext("Ouverte · %{deadline}", deadline: deadline_text(seq, today))
    end
  end

  defp not_open_message, do: gettext("La saisie de cette séquence n'est pas encore ouverte.")

  defp empty_message(true, _locked?), do: not_open_message()
  defp empty_message(false, true), do: gettext("Cette séquence est verrouillée.")

  defp empty_message(false, false),
    do:
      gettext(
        "Créez la première : son type, un nom (« Devoir 1 »), la note maximale. La liste des élèves s'affiche ensuite pour la saisie."
      )

  defp missing_line(_missing, nil, _locked?), do: nil
  defp missing_line(_missing, _seq, true), do: nil
  defp missing_line(0, _seq, false), do: gettext("Toutes les notes sont saisies.")

  defp missing_line(missing, seq, false),
    do:
      ngettext(
        "%{count} note à saisir avant le %{date}",
        "%{count} notes à saisir avant le %{date}",
        missing,
        date: Dates.day_month(seq.grade_entry_deadline)
      )

  # « Devoir 1 · 3e A » (or the course's name for a combined course).
  defp side_title(column, groups, course, _seq) do
    who = if course, do: course.label, else: hd(groups).class_group.label
    column.label <> " · " <> who
  end

  # Shown students only; a mark of an exempt student still makes the server refuse.
  defp no_marks?(loaded), do: Enum.all?(loaded, fn {_id, text} -> text in [nil, ""] end)

  defp delete_confirm(column, false),
    do: gettext("Supprimer l'évaluation « %{label} » ?", label: column.label)

  defp delete_confirm(column, true),
    do:
      gettext("Supprimer l'évaluation « %{label} » de toutes les classes du cours ?",
        label: column.label
      )

  attr :seq, :map, required: true
  attr :assessment, :map, default: nil

  defp locked_banner(assigns) do
    ~H"""
    <div
      id="locked-banner"
      class="flex flex-wrap items-center gap-3 rounded-box border border-info/50 bg-info/15 px-4 py-3 text-sm"
    >
      <.icon name="hero-lock-closed" class="size-4 text-info" />
      <span class="flex-1">
        {gettext("Séquence %{n} verrouillée depuis le %{date}",
          n: @seq.number,
          date: @seq.grade_entry_deadline |> Date.add(1) |> Dates.day_month()
        )}
      </span>
      <.link
        :if={@assessment}
        id="locked-request-link"
        navigate={~p"/school/corrections/new?assessment=#{@assessment.id}"}
        class="link font-semibold link-hover"
      >
        {gettext("Demander une correction →")}
      </.link>
    </div>
    """
  end

  attr :seq, :map, required: true

  defp upcoming_banner(assigns) do
    ~H"""
    <div
      id="upcoming-banner"
      class="flex items-start gap-3 rounded-box border border-base-300 bg-base-200/60 px-4 py-3 text-sm"
    >
      <.icon name="hero-calendar-days" class="mt-0.5 size-4 text-base-content/70" />
      <span>
        {gettext("La saisie ouvre le %{date}, au début de la séquence %{n}.",
          date: Dates.day_month(@seq.start_date),
          n: @seq.number
        )}
      </span>
    </div>
    """
  end

  attr :names, :list, required: true

  defp pending_makeups(assigns) do
    ~H"""
    <div :if={@names != []} id="pending-makeups" class="alert alert-warning text-sm">
      <.icon name="hero-arrow-path" class="size-4" />
      <span>{gettext("Rattrapage attendu :")} {Enum.join(@names, ", ")}</span>
    </div>
    """
  end
end
