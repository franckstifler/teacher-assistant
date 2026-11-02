defmodule TeacherAssistantWeb.Teacher.MarksLive do
  @moduledoc """
  « Saisie des notes » (spec 2026-10-09 §2.3): one assessment column of a course, each
  mark saved when its cell loses focus. A combined course shows the union roster by
  class; its column is one real `Assessment` per member class and a student's mark
  always lands on their own class's.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.TeachingNav
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.{CombinedCourse, Marks}
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.{Lock, MarkEntry, Reference}
  alias TeacherAssistantWeb.Dates
  alias TeacherAssistantWeb.Teacher.MarksComponents

  def mount(%{"id" => ctx_id}, _session, socket) do
    scope = socket.assigns.current_scope

    case Curriculum.fetch_assigned_teaching_context(scope, ctx_id) do
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
    |> assign(:ctx, ctx)
    |> assign(:grading_rules, Assessment.grading_rules(scope))
    |> assign(:sequences, if(year, do: Organization.list_sequences(scope, year), else: []))
    |> assign(:student_group, student_group(socket.assigns.groups))
    |> assign(errors: %{}, saved_at: nil, today: Reference.today())
    |> assign(:course_tabs, course_tabs(scope, ctx))
    |> assign(:apc?, apc?(scope, socket.assigns.groups))
    |> assign(competence: nil, competence_reminder_dismissed?: false)
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

  # The teacher's courses, each linking to its own marks page.
  defp course_tabs(scope, ctx) do
    for unit <- Curriculum.list_units_for_scope(scope) do
      %{
        label: Curriculum.unit_label(unit),
        context_id: Curriculum.unit_select_id(scope, unit),
        current?: current_unit?(unit, ctx)
      }
    end
  end

  defp current_unit?({:course, course}, ctx), do: course.id == ctx.combined_course_id
  defp current_unit?({:solo, tc}, ctx), do: tc.id == ctx.id

  # student id => class group id, to route a mark to the student's own class.
  defp student_group(groups),
    do: for(g <- groups, s <- g.students, into: %{}, do: {s.id, g.class_group.id})

  # School assessment types and default maximum for the "new assessment" form.
  defp assign_assessment_defaults(socket, scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    assign(socket,
      assessment_types: Assessment.list_assessment_types(scope),
      default_max: profile.default_max_score
    )
  end

  # Students whose make-up is still expected on the selected column (make-up rule).
  defp assign_pending(socket) do
    %{current_scope: scope, grading_rules: rules} = socket.assigns

    by_student =
      socket.assigns.column
      |> column_assessments()
      |> Enum.flat_map(&Assessment.list_marks(scope, &1))
      |> Enum.group_by(& &1.student_id)

    pending =
      for s <- all_students(socket.assigns),
          Marks.makeup_pending?(Map.get(by_student, s.id, []), rules),
          do: s.full_name

    assign(socket, :pending_makeups, pending)
  end

  # "New assessment" params: drop an empty type, name it after its type when the
  # label is blank ("Devoir surveillé 2"), and keep a valid maximum (otherwise the
  # school default applies).
  defp normalize_assessment_params(params, socket) do
    type = Enum.find(socket.assigns.assessment_types, &(&1.id == params["assessment_type_id"]))

    label =
      case {String.trim(params["label"] || ""), type} do
        {"", %{} = type} -> "#{type.name} #{next_type_number(socket, type)}"
        {label, _} -> label
      end

    max =
      case TeacherAssistant.Curriculum.parse_coefficient(params["max_score"] || "") do
        {:ok, dec} -> dec
        :error -> nil
      end

    %{"label" => label}
    |> then(&if(type, do: Map.put(&1, "assessment_type_id", type.id), else: &1))
    |> then(&if(max, do: Map.put(&1, "max_score", max), else: &1))
  end

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

  defp mark_field(%{status: status, score: score}), do: MarkEntry.format(status, score)

  defp all_students(%{groups: groups}), do: Enum.flat_map(groups, & &1.students)

  defp entered_count(students, loaded),
    do: Enum.count(students, &(Map.get(loaded, &1.id) not in [nil, ""]))

  defp preview_average(_students, nil, _scores, _rules), do: nil

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

  # Blank scaffold for the "new assessment" toolbar form in combined mode.
  # Backed by the real `Assessment :create` action so the `:label` field
  # renders as an `AshPhoenix.Form` field; `as: "assessment"` keeps the
  # posted param key (`%{"assessment" => %{"label" => …}}`) exactly as
  # before. In combined mode the multi-class create runs through
  # `Assessment.create_combined_assessment/4` directly (it never calls
  # `AshPhoenix.Form.submit/2` on this form), so no `prepare_source` is
  # needed here.
  defp assessment_form(scope) do
    TeacherAssistant.Academics.Assessment
    |> AshPhoenix.Form.for_create(:create, as: "assessment", scope: scope)
    |> to_form()
  end

  # Solo mode: the "new assessment" toolbar form, with the server-controlled
  # context/sequence ids set on the changeset at build time via
  # `prepare_source` (never merged into the submitted params). The tenant and
  # actor travel on the form's `scope:`. `seq` is a *live* value — the
  # operator can switch séquence via the "seq" selector — so callers must
  # rebuild this form on mount and again whenever `seq` changes (see
  # `handle_params/3`). Falls back to the plain scaffold when there's no
  # séquence yet; the toolbar form itself is only rendered when `@seq` is
  # present, so that scaffold is never actually submitted.
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
  # `solo_assessment_form/3` (assigned at mount and kept fresh in
  # `handle_params/3`) — no second `for_create` here. This is behaviourally
  # identical to the old `Assessment.create_assessment/4` (which was itself
  # `for_create(:create)` + `Ash.create/1` with those two ids merged). Errors
  # keep the original flash; on success, the `push_patch` re-runs
  # `handle_params/3`, which reassigns a fresh scaffold form.
  defp new_solo_assessment(socket, params) do
    case socket.assigns.seq do
      %{} = seq ->
        case AshPhoenix.Form.submit(socket.assigns.new_assessment_form, params: params) do
          {:ok, a} ->
            {:noreply,
             push_patch(socket,
               to:
                 ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}"
             )}

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
      {:noreply,
       push_patch(socket,
         to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{id}"
       )}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    seq = pick_seq(socket.assigns.sequences, params["seq"])
    columns = columns(socket, seq)
    # The asked column, else the first: the sheet is never hidden behind the select.
    column = pick(columns, params["assessment"]) || List.first(columns)
    loaded = saved_marks(scope, column)

    {:noreply,
     socket
     |> warn_dropped_errors()
     |> assign(seq: seq, upcoming?: seq != nil and Lock.not_started?(seq))
     # `locked?`: no entry at all — past the deadline, or not started yet (`upcoming?`).
     |> assign(locked?: seq != nil and (Lock.locked?(seq) or Lock.not_started?(seq)))
     |> assign(columns: columns, column: column)
     |> assign(scores: loaded, loaded: loaded, errors: %{})
     |> assign(:new_assessment_form, new_assessment_form(socket, seq))
     |> load_competence()
     |> assign_pending()}
  end

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

  # The phone pickers: another course opens its marks page (same séquence), a séquence
  # patches this one.
  def handle_event("pick", %{"_target" => ["context"], "context" => context} = params, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/teacher/contexts/#{context}/marks?#{seq_query(params)}")}
  end

  def handle_event("pick", params, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?#{seq_query(params)}"
       )}

  def handle_event("save_competence", %{"competence" => %{"text" => text}}, socket),
    do: save_competence(socket, text)

  def handle_event("save_competence_blur", %{"value" => text}, socket) do
    if String.trim(text) == String.trim(socket.assigns.competence || ""),
      do: {:noreply, socket},
      else: save_competence(socket, text)
  end

  def handle_event("dismiss_competence_reminder", _params, socket),
    do: {:noreply, assign(socket, :competence_reminder_dismissed?, true)}

  def handle_event("select_assessment", %{"assessment" => aid}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{socket.assigns.seq.id}&assessment=#{aid}"
     )}
  end

  def handle_event(event, _params, %{assigns: %{upcoming?: true}} = socket)
      when event in ["new_assessment", "save_mark"],
      do: {:noreply, put_flash(socket, :error, not_open_message())}

  def handle_event("new_assessment", _params, %{assigns: %{locked?: true}} = socket),
    do: {:noreply, put_flash(socket, :error, gettext("Séquence verrouillée."))}

  def handle_event("new_assessment", %{"assessment" => p}, socket) do
    case socket.assigns[:course] do
      %CombinedCourse{} = course ->
        new_combined_assessment(socket, course, normalize_assessment_params(p, socket))

      _ ->
        new_solo_assessment(socket, normalize_assessment_params(p, socket))
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
    %{current_scope: scope, column: column, ctx: ctx, seq: seq} = socket.assigns

    case Assessment.delete_assessments(scope, column_assessments(column)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Évaluation supprimée."))
         |> push_patch(to: ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")}

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

  def handle_event("save_mark", _params, %{assigns: %{locked?: true}} = socket),
    do: {:noreply, put_flash(socket, :error, gettext("Séquence verrouillée."))}

  def handle_event("save_mark", %{"student" => id, "value" => raw}, socket) do
    # An absent cell is disabled; the blur a browser may fire as it becomes disabled
    # carries its empty value and must not undo the absence (only the toggle does).
    if MarkEntry.parse(raw) == {:ok, :blank} and
         MarkEntry.parse(socket.assigns.loaded[id]) == {:ok, :absent} do
      {:noreply, socket}
    else
      socket = assign(socket, :scores, Map.put(socket.assigns.scores, id, raw))

      case MarkEntry.parse(raw) do
        :error -> {:noreply, put_error(socket, id, :invalid)}
        {:ok, entry} -> write_mark(socket, id, entry)
      end
    end
  end

  def handle_event("toggle_absent", _params, %{assigns: %{locked?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle_absent", %{"student" => id}, socket) do
    entry =
      if MarkEntry.parse(socket.assigns.loaded[id]) == {:ok, :absent}, do: :blank, else: :absent

    write_mark(socket, id, entry)
  end

  # Writes one student's mark to their own class's assessment — only when it differs
  # from what this page loaded, so a blur never rewrites (nor overwrites another
  # device's newer value of) an untouched mark.
  defp write_mark(socket, id, entry) do
    %{current_scope: scope, loaded: loaded} = socket.assigns

    cond do
      not Map.has_key?(socket.assigns.student_group, id) ->
        {:noreply, socket}

      same_entry?(entry, MarkEntry.parse(Map.get(loaded, id))) ->
        {:noreply,
         socket
         |> clear_error(id)
         |> assign(:scores, Map.put(socket.assigns.scores, id, Map.get(loaded, id, "")))}

      not TeacherAssistant.Scope.school_verified?(scope) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("École en attente de vérification — enregistrement indisponible.")
         )}

      true ->
        case assessment_for(socket.assigns, id) do
          nil -> {:noreply, put_error(socket, id, :no_assessment)}
          assessment -> upsert(socket, assessment, id, entry)
        end
    end
  end

  defp upsert(socket, assessment, id, entry) do
    attrs = Map.put(entry_attrs(entry), :student_id, id)

    case Assessment.upsert_marks(socket.assigns.current_scope, assessment, [attrs]) do
      :ok ->
        text = mark_text(entry)

        {:noreply,
         socket
         |> clear_error(id)
         |> assign(:saved_at, Reference.now())
         |> assign(:loaded, Map.put(socket.assigns.loaded, id, text))
         |> assign(:scores, Map.put(socket.assigns.scores, id, text))
         |> assign_pending()}

      {:error, :out_of_range} ->
        {:noreply, put_error(socket, id, :out_of_range)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      _ ->
        {:noreply, failed(socket, id)}
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
    message = gettext("Note entre 0 et %{max}", max: max_label(socket.assigns.column))
    assign(socket, :errors, Map.put(socket.assigns.errors, id, message))
  end

  defp clear_error(socket, id), do: assign(socket, :errors, Map.delete(socket.assigns.errors, id))

  # The field text a stored entry shows, as `mark_field/1` renders a stored mark.
  defp mark_text(:blank), do: ""
  defp mark_text({:graded, d}), do: MarkEntry.format(:graded, d)
  defp mark_text(status), do: MarkEntry.format(status, nil)

  defp max_label(%{max_score: %Decimal{} = m}),
    do: m |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp max_label(_column), do: "20"

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

  defp save_state(assigns) do
    ~H"""
    <p
      :if={@errors != %{}}
      id="save-state"
      class="ta-num rounded-full bg-warning/20 px-3 py-1 text-sm font-semibold text-warning"
    >
      {ngettext(
        "Erreur : %{count} note à corriger",
        "Erreur : %{count} notes à corriger",
        map_size(@errors)
      )}
    </p>
    <p
      :if={@errors == %{} and @saved_at != nil}
      id="save-state"
      class="ta-num flex items-center gap-1.5 rounded-full bg-primary/15 px-3 py-1 text-sm font-semibold text-primary"
    >
      <.icon name="hero-check-circle" class="size-4" />
      {gettext("Enregistré · %{time}", time: Calendar.strftime(@saved_at, "%H:%M"))}
    </p>
    """
  end

  attr :seq, :map, required: true
  attr :text, :string, default: nil
  attr :locked?, :boolean, default: false
  attr :reminder?, :boolean, default: false

  # Spec bulletin v2 §6: the competence printed on the APC report card, one per séquence.
  defp competence_panel(assigns) do
    ~H"""
    <div class="ta-panel flex flex-col gap-2">
      <div
        :if={@reminder? and not @locked?}
        id="competence-reminder"
        role="status"
        class="flex items-start justify-between gap-3 rounded-[0.5rem] border border-warning/40 bg-warning/10 px-3 py-2 text-sm"
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
      <.form
        for={to_form(%{"text" => @text}, as: :competence)}
        id="sequence-competence"
        phx-submit="save_competence"
        class="flex flex-wrap items-end gap-2"
      >
        <div class="min-w-0 flex-1">
          <.input
            name="competence[text]"
            id="competence-text"
            value={@text}
            label={gettext("Compétence évaluée (séquence %{n})", n: @seq.number)}
            maxlength="140"
            disabled={@locked?}
            phx-blur="save_competence_blur"
          />
        </div>
        <button :if={not @locked?} type="submit" class="btn btn-sm btn-primary mb-2">
          {gettext("Enregistrer")}
        </button>
      </.form>
    </div>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :students, all_students(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      nav={["courses"]}
    >
      <section id="teacher-marks" class="space-y-4">
        <.teaching_nav context_id={@ctx.id} label={@title} current={:marks} />
        <%!-- The breadcrumb above names the course; no eyebrow repeats it. --%>
        <.page_header title={gettext("Saisie des notes")}>
          <:actions>
            <.save_state errors={@errors} saved_at={@saved_at} />
          </:actions>
        </.page_header>

        <.competence_panel
          :if={@apc? and @seq}
          seq={@seq}
          text={@competence}
          locked?={@locked?}
          reminder?={is_nil(@competence) and not @competence_reminder_dismissed?}
        />

        <div id="marks-toolbar" class="ta-panel flex flex-col gap-3">
          <%!-- Phones: the course and the séquence as two compact selects. --%>
          <form
            :if={length(@course_tabs) > 1 or @sequences != []}
            id="marks-pickers"
            phx-change="pick"
            class="grid gap-2 sm:hidden"
          >
            <select
              :if={length(@course_tabs) > 1}
              id="pick-course"
              name="context"
              aria-label={gettext("Mes cours")}
              class="select select-bordered select-sm w-full"
            >
              <option
                :for={tab <- @course_tabs}
                value={tab.context_id}
                selected={tab.current?}
              >
                {tab.label}
              </option>
            </select>
            <select
              :if={@sequences != []}
              id="pick-seq"
              name="seq"
              aria-label={gettext("Séquence")}
              class="select select-bordered select-sm w-full"
            >
              <option :for={s <- @sequences} value={s.id} selected={@seq && @seq.id == s.id}>
                {seq_tab_label(s, @today)}
              </option>
            </select>
          </form>

          <div class="hidden flex-wrap items-center gap-2 sm:flex">
            <nav
              :if={length(@course_tabs) > 1}
              id="course-tabs"
              aria-label={gettext("Mes cours")}
              phx-hook="ScrollActiveTab"
              class="flex max-w-full gap-1 overflow-x-auto rounded-box bg-base-200 p-1"
            >
              <.link
                :for={tab <- @course_tabs}
                navigate={~p"/teacher/contexts/#{tab.context_id}/marks"}
                aria-current={tab.current? && "page"}
                class={[
                  "whitespace-nowrap rounded-[0.5rem] px-3 py-1.5 text-sm font-semibold transition-colors",
                  if(tab.current?,
                    do: "bg-primary text-primary-content",
                    else: "text-base-content/70 hover:bg-base-300"
                  )
                ]}
              >
                {tab.label}
              </.link>
            </nav>

            <div
              :if={@sequences != []}
              id="seq-tabs"
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
                    do: "bg-base-content text-base-100 font-semibold",
                    else: "text-base-content/70 hover:bg-base-200"
                  )
                ]}
              >
                {seq_tab_label(s, @today)}
              </.link>
            </div>
          </div>

          <div class="flex flex-wrap items-end gap-2">
            <.assessment_controls
              seq={@seq}
              locked?={@locked?}
              columns={@columns}
              column={@column}
              deletable?={@column != nil and (!@locked? or @upcoming?) and no_marks?(@loaded)}
              combined?={@course != nil}
              form={@new_assessment_form}
              assessment_types={@assessment_types}
              default_max={@default_max}
            />
          </div>
        </div>

        <.locked_banner :if={@locked? and !@upcoming?} seq={@seq} assessment={@column} />
        <.upcoming_banner :if={@upcoming?} seq={@seq} />
        <.open_banner :if={@seq && !@locked?} seq={@seq} today={@today} />

        <div :if={@seq && @columns == []} id="marks-empty">
          <.empty_state
            icon="hero-pencil-square"
            title={gettext("Aucune évaluation pour la séquence %{n}", n: @seq.number)}
            message={
              cond do
                @upcoming? ->
                  not_open_message()

                @locked? ->
                  gettext("Cette séquence est verrouillée.")

                true ->
                  gettext(
                    "Créez la première ci-dessus : son type, un nom (« Devoir 1 »), la note maximale, puis Ajouter. La liste des élèves s'affiche ensuite pour la saisie."
                  )
              end
            }
          />
        </div>

        <div
          :if={@column}
          class="grid grid-cols-[minmax(0,1fr)] items-start gap-4 lg:grid-cols-[minmax(0,1fr)_260px]"
        >
          <div class="space-y-3">
            <.pending_makeups names={@pending_makeups} />
            <div class="ta-panel overflow-x-auto !p-0">
              <table id="marks-table" class="table table-sm" phx-hook=".MarksGrid">
                <thead>
                  <tr>
                    <th>{gettext("N°")}</th>
                    <th>{gettext("Élève")}</th>
                    <th class="whitespace-nowrap">
                      {@column.label} · /{max_label(@column)}
                    </th>
                    <th>{gettext("Absent")}</th>
                    <th>{gettext("Appréciation")}</th>
                  </tr>
                </thead>
                <%= for {group, offset} <- group_offsets(@groups) do %>
                  <tbody id={"marks-class-#{group.class_group.id}"}>
                    <tr :if={@course}>
                      <th colspan="5" class="ta-eyebrow bg-base-200/60">
                        {group.class_group.label}
                      </th>
                    </tr>
                    <MarksComponents.mark_row
                      :for={{s, i} <- Enum.with_index(group.students, offset + 1)}
                      student={s}
                      n={i}
                      value={Map.get(@scores, s.id, "")}
                      saved={Map.get(@loaded, s.id, "")}
                      error={@errors[s.id]}
                      locked?={@locked?}
                      max={@column.max_score}
                      grading_rules={@grading_rules}
                    />
                  </tbody>
                <% end %>
              </table>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".MarksGrid">
                // Enter moves to the next student's cell (its blur saves this one).
                export default {
                  mounted() {
                    this.el.addEventListener("keydown", (e) => {
                      const input = e.target.closest("input[data-mark-input]")
                      if (!input) return
                      if (e.key === "Enter") {
                        e.preventDefault()
                        const inputs = [...this.el.querySelectorAll("input[data-mark-input]:not([disabled])")]
                        const next = inputs[inputs.indexOf(input) + 1]
                        next ? next.focus() : input.blur()
                      }
                    })
                  }
                }
              </script>
            </div>
          </div>

          <aside class="space-y-3 lg:sticky lg:top-4">
            <MarksComponents.side_panel
              title={side_title(@groups, @course, @seq)}
              done={entered_count(@students, @loaded)}
              total={length(@students)}
              average={fmt_avg(preview_average(@students, @column, @loaded, @grading_rules))}
              missing={
                missing_line(
                  length(@students) - entered_count(@students, @loaded),
                  @seq,
                  @locked?
                )
              }
            />
            <div id="marks-shortcuts" class="ta-leaf space-y-1.5 text-sm">
              <p class="ta-eyebrow">{gettext("Raccourcis")}</p>
              <p>
                <kbd class="kbd kbd-sm">{gettext("Entrée")}</kbd> {gettext("élève suivant")}
              </p>
              <p>
                <kbd class="kbd kbd-sm">a</kbd> {gettext(
                  "puis Entrée : absent · abj : absence justifiée"
                )}
              </p>
              <p class="text-base-content/70">
                {gettext("Virgule ou point acceptés : 12,5 = 12.5")}
              </p>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # « Séquence 2 · ouverte » / « · verrouillée » / « · à venir ».
  defp seq_query(%{"seq" => seq}) when seq != "", do: [seq: seq]
  defp seq_query(_params), do: []

  defp seq_tab_label(seq, today) do
    base = gettext("Séquence %{n}", n: seq.number)

    cond do
      Lock.locked?(seq, today) -> base <> " · " <> gettext("verrouillée")
      Lock.not_started?(seq, today) -> base <> " · " <> gettext("à venir")
      true -> base <> " · " <> gettext("ouverte")
    end
  end

  defp not_open_message, do: gettext("La saisie de cette séquence n'est pas encore ouverte.")

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

  # Each group with the row number its first student follows.
  defp group_offsets(groups) do
    {pairs, _total} =
      Enum.map_reduce(groups, 0, fn g, offset -> {{g, offset}, offset + length(g.students)} end)

    pairs
  end

  defp side_title(groups, course, seq) do
    who = if course, do: course.label, else: hd(groups).class_group.label
    if seq, do: who <> " · " <> gettext("Séquence %{n}", n: seq.number), else: who
  end

  attr :seq, :map, default: nil
  attr :locked?, :boolean, required: true
  attr :columns, :list, required: true
  attr :column, :map, default: nil
  attr :deletable?, :boolean, default: false
  attr :combined?, :boolean, default: false
  attr :form, :any, required: true
  attr :assessment_types, :list, required: true
  attr :default_max, :any, required: true

  defp assessment_controls(assigns) do
    ~H"""
    <form
      :if={@seq && @columns != []}
      id="assessment-select"
      phx-change="select_assessment"
      class="min-w-36 flex-1"
    >
      <.input
        type="select"
        name="assessment"
        value={@column && @column.id}
        label={gettext("Évaluation")}
        options={for a <- @columns, do: {a.label, a.id}}
      />
    </form>

    <button
      :if={@deletable?}
      id="delete-assessment"
      type="button"
      phx-click="delete_assessment"
      data-confirm={delete_confirm(@column, @combined?)}
      class="btn btn-ghost mb-2 gap-1.5 text-error transition-colors hover:bg-error/10"
    >
      <.icon name="hero-trash" class="size-4" />
      {gettext("Supprimer")}
    </button>

    <.form
      :if={@seq && !@locked?}
      for={@form}
      id="new-assessment-form"
      phx-submit="new_assessment"
      class="grid flex-1 basis-full grid-cols-2 items-end gap-x-2 gap-y-3 sm:flex sm:basis-auto"
    >
      <.input
        type="select"
        name="assessment[assessment_type_id]"
        value=""
        label={gettext("Type")}
        options={[{gettext("Choisir"), ""} | for(t <- @assessment_types, do: {t.name, t.id})]}
        class="select w-full sm:min-w-[9rem]"
      />
      <.input
        field={@form[:label]}
        label={gettext("Nouvelle évaluation")}
        placeholder={gettext("ex. Devoir 1")}
      />
      <.input
        type="text"
        inputmode="decimal"
        name="assessment[max_score]"
        label={gettext("Sur")}
        value={Decimal.to_string(@default_max, :normal)}
        class="input w-full sm:w-20"
      />
      <.button
        type="submit"
        class={
          if(@columns == [],
            do: "btn btn-primary w-full sm:w-auto",
            else: "btn btn-outline w-full sm:w-auto"
          )
        }
      >
        {gettext("Ajouter")}
      </.button>
    </.form>
    """
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
        {gettext("Séquence %{n} verrouillée depuis le %{date}.",
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
  attr :today, Date, required: true

  defp open_banner(assigns) do
    ~H"""
    <div
      id="open-banner"
      class="flex items-start gap-3 rounded-box border border-primary/45 bg-primary/10 px-4 py-3 text-sm"
    >
      <.icon name="hero-pencil-square" class="mt-0.5 size-4 text-primary" />
      <span>
        {gettext(
          "Saisie ouverte jusqu'au %{date} (J-%{n}). Chaque note est enregistrée dès que vous quittez la case.",
          date: Dates.day_month(@seq.grade_entry_deadline),
          n: max(Date.diff(@seq.grade_entry_deadline, @today), 0)
        )}
      </span>
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

  defp save_competence(%{assigns: %{seq: %{} = seq, ctx: ctx}} = socket, text) do
    case Assessment.put_sequence_competence(socket.assigns.current_scope, ctx, seq, text) do
      :ok ->
        {:noreply, socket |> load_competence() |> assign(:saved_at, Reference.now())}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Compétence non enregistrée."))}
    end
  end

  defp save_competence(socket, _text), do: {:noreply, socket}
end
