defmodule TeacherAssistantWeb.School.RollCall do
  @moduledoc """
  One roll call (class × period × date) as plain state, shared by the roll-call
  page (`AttendanceLive`) and the teacher's day (`MyDayLive`): resolve and
  authorize it, toggle a student, record it, and render it as the mockup's panel.

  The roll starts with every student present (the cahier d'appel default); the
  teacher only taps the absent and late few. `taken?` tells "all present" apart
  from "not done yet".
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.{Attendance, Curriculum, Discipline, Enrollment, FeeControl, Scope}
  alias TeacherAssistant.Academics.{AttendanceStatus, CombinedCourse, TeachingContext}
  alias TeacherAssistant.Academics.TimetableSlot

  @statuses [:present, :absent, :late]
  @valid_statuses Map.new(@statuses, &{Atom.to_string(&1), &1})

  @doc """
  Opens the roll call of class `cg_id` at `period_id` on `date`: `{:ok, roll}`,
  `{:error, :not_found}` or `{:error, :forbidden}` (neither the course's teacher
  nor a conduct manager).
  """
  def open(%Scope{} = scope, cg_or_course, period_id, %Date{} = date, opts \\ []) do
    with {:ok, cg, course} <- fetch_unit(scope, cg_or_course),
         {:ok, period} <- fetch_period(scope, period_id) do
      slot = slot(scope, cg, date, period.id)
      conduct? = Discipline.can_manage_conduct?(scope)

      # Spec 2026-11-12: `context: :mine` resolves the actor's own assignment (or
      # course) whatever the slot holds; a lesson is moved when the slot is not its.
      # My own earlier roll call at this period reopens under its context (a
      # reopened moved lesson), whatever the slot says.
      teaching_context =
        case {Keyword.get(opts, :context), Attendance.held_context(scope, cg, period, date)} do
          {_, %{own?: true, context: tc}} -> tc
          {:mine, _} -> my_context(scope, cg, course)
          _ -> resolve_teaching_context(scope, cg, slot)
        end

      course = course || combined_course_for(scope, teaching_context)

      moved? =
        teaching_context != nil and
          (slot == nil or slot.teaching_context_id != teaching_context.id)

      held = held_by_other(scope, cg, course, period, date)

      cond do
        not authorized?(scope, teaching_context) ->
          {:error, :forbidden}

        held != nil and not conduct? ->
          {:error, {:held_by, Map.merge(held, %{class: cg.label, time: hm(period.start_time)})}}

        # The date rule binds teachers; a conduct manager corrects any day.
        moved? and not conduct? and too_early?(period, date) ->
          {:error, :not_started}

        moved? and not conduct? and too_old?(date) ->
          {:error, :too_old}

        true ->
          # A conduct manager correcting a colleague's roll call keeps its context.
          teaching_context = if held, do: held.context, else: teaching_context

          roll = %{
            cg: cg,
            period: period,
            date: date,
            teaching_context: teaching_context,
            course: course,
            moved?: moved?,
            # A2: only a page that shows the « aussi pour la 2e heure » box may
            # write the following hours (Ma journée); a moved lesson has no 2e heure.
            offer_following?: Keyword.get(opts, :following, false) and not moved?
          }

          {:ok, scope |> reload(roll) |> put_adjacent(scope) |> put_moved_from(scope)}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "« À la place de »: `period_id` (one of `roll.moved_from_options`) or `\"\"` for none."
  def set_moved_from(roll, ""), do: Map.put(roll, :moved_from, nil)

  def set_moved_from(roll, period_id),
    do:
      Map.put(
        roll,
        :moved_from,
        Enum.find_value(roll.moved_from_options, &(&1.period.id == period_id && &1.period))
      )

  @doc "The sentence for an `open/5` or `record/2` refusal (spec 2026-11-12)."
  def error_message({:held_by, who}),
    do:
      gettext("Un appel a déjà été fait pour %{class} à %{time} (%{teacher}, %{subject}).",
        class: who.class,
        time: who.time,
        teacher: TeacherAssistant.Accounts.User.display_name(who.teacher),
        subject: who.subject
      )

  def error_message(:not_started), do: gettext("Ce créneau n'a pas encore commencé.")

  def error_message(:too_old),
    do: gettext("Cette journée n'est plus modifiable depuis le téléphone.")

  # A course param (`"course:<id>"`) opens the roll call of the course's first member
  # class; a class id, that class.
  defp fetch_unit(scope, "course:" <> id) do
    with {:ok, %CombinedCourse{} = course} <- Curriculum.get_course(scope, id),
         [first | _] <- Curriculum.contexts_of_course!(course.id, scope: scope),
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, first.class_group_id) do
      {:ok, cg, course}
    else
      _ -> {:error, :not_found}
    end
  end

  defp fetch_unit(scope, cg_id) do
    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, cg_id), do: {:ok, cg, nil}
  end

  defp my_context(scope, cg, %CombinedCourse{} = course),
    do: Enum.find(course_contexts(scope, course), &(&1.class_group_id == cg.id))

  defp my_context(scope, cg, nil), do: resolve_teaching_context(scope, cg, nil)

  defp course_contexts(scope, %CombinedCourse{id: id}),
    do: Curriculum.contexts_of_course!(id, scope: scope)

  defp held_by_other(scope, cg, nil, period, date),
    do: Attendance.held_by_other_context(scope, cg, period, date)

  defp held_by_other(scope, _cg, %CombinedCourse{} = course, period, date) do
    scope
    |> course_contexts(course)
    |> Enum.find_value(fn tc ->
      case Enrollment.fetch_owned_class_group(scope, tc.class_group_id) do
        {:ok, cg} -> Attendance.held_by_other_context(scope, cg, period, date)
        _ -> nil
      end
    end)
  end

  # Spec 2026-11-12: today, a moved roll call waits for the period to start; an
  # earlier day of the current week is open at any period; nothing before Monday.
  defp too_early?(period, date) do
    today = TeacherAssistant.Academics.Reference.today()

    case Date.compare(date, today) do
      :gt ->
        true

      :eq ->
        Time.compare(
          period.start_time,
          NaiveDateTime.to_time(TeacherAssistant.Academics.Reference.now())
        ) == :gt

      :lt ->
        false
    end
  end

  defp too_old?(date),
    do:
      Date.compare(date, Date.beginning_of_week(TeacherAssistant.Academics.Reference.today())) ==
        :lt

  defp put_moved_from(%{moved?: false} = roll, _scope),
    do: Map.merge(roll, %{moved_from_options: [], moved_from: nil})

  defp put_moved_from(roll, scope) do
    options = Attendance.own_lessons_for_moved_from(scope, unit(roll), roll.date)

    Map.merge(roll, %{
      moved_from_options: options,
      moved_from: List.first(options) && hd(options).period
    })
  end

  defp unit(%{course: %CombinedCourse{} = course}), do: course
  defp unit(%{cg: cg, teaching_context: tc}), do: {cg, tc}

  defp hm(time), do: Calendar.strftime(time, "%H:%M")

  @doc "Sets one student's status (`\"present\" | \"absent\" | \"late\"`); unknown ids or statuses are ignored."
  def set(roll, enrollment_id, status) do
    # Fees 2: a student sent home for fees is either back in the room (present) or sent
    # home again — never absent or late.
    status =
      if MapSet.member?(roll.sent_home, enrollment_id),
        do: Map.get(%{"present" => :present, "sent_home" => :sent_home}, status),
        else: Map.get(@valid_statuses, status)

    if status && Enum.any?(roll.students, &(&1.enrollment_id == enrollment_id)) do
      roll = put_in(roll, [:marks, enrollment_id], status)
      # Minutes belong to a late only (spec KLM2).
      if status == :late, do: roll, else: put_in(roll, [:minutes, enrollment_id], nil)
    else
      roll
    end
  end

  @doc """
  A tap on a row's toggle (UX refonte 2026-11-03): Absent or Retard sets it, the
  active one tapped again puts the student back to present; anything else is `set/3`.
  """
  def toggle(roll, enrollment_id, status) when status in ["absent", "late"] do
    if roll.marks[enrollment_id] == Map.fetch!(@valid_statuses, status),
      do: set(roll, enrollment_id, "present"),
      else: set(roll, enrollment_id, status)
  end

  def toggle(roll, enrollment_id, status), do: set(roll, enrollment_id, status)

  @doc "Sets late minutes from the row inputs (`%{enrollment_id => \"25\"}`); blanks and bad values clear them."
  def set_minutes(roll, %{} = params) do
    Enum.reduce(params, roll, fn {enrollment_id, value}, roll ->
      if Map.has_key?(roll.marks, enrollment_id) do
        put_in(roll, [:minutes, enrollment_id], parse_minutes(value))
      else
        roll
      end
    end)
  end

  defp parse_minutes(value) do
    case Integer.parse(String.trim(to_string(value))) do
      {n, ""} when n in 1..240 -> n
      _ -> nil
    end
  end

  @doc "Records the roll: `{:ok, roll}` (reloaded) or `{:error, :unverified | :forbidden | :failed}`."
  def record(%Scope{} = scope, roll) do
    cond do
      not Scope.school_verified?(scope) ->
        {:error, :unverified}

      not authorized?(scope, roll.teaching_context) ->
        {:error, :forbidden}

      true ->
        marks =
          Enum.map(roll.students, fn %{enrollment_id: id} ->
            status = Map.fetch!(roll.marks, id)
            {id, status, if(status == :late, do: roll.minutes[id])}
          end)

        # A2: the following hours of the same lesson, when the box is on — minus any
        # taken since the page opened (a later hour is never overwritten). A late at
        # this hour is in the room for the next ones.
        following =
          if roll[:record_following],
            do: Enum.take_while(roll.following, &(not taken?(scope, roll, &1))),
            else: []

        following_marks =
          Enum.map(marks, fn {id, status, _} ->
            {id, if(status == :late, do: :present, else: status), nil}
          end)

        result =
          if roll[:moved?],
            do:
              Attendance.record_moved_period(scope, unit(roll), roll.period, roll.date, marks,
                moved_from: roll[:moved_from]
              ),
            else: write_all(scope, roll, marks, following, following_marks)

        case result do
          {:ok, _count} ->
            {:ok,
             scope
             |> reload(roll)
             |> put_adjacent(scope)
             |> put_moved_from(scope)
             |> Map.put(:saved_periods, 1 + length(following))}

          {:error, %Ash.Error.Forbidden{}} ->
            {:error, :forbidden}

          {:error, {:held_by, who}} ->
            {:error,
             {:held_by, Map.merge(who, %{class: roll.cg.label, time: hm(roll.period.start_time)})}}

          {:error, _reason} ->
            {:error, :failed}
        end
    end
  end

  @doc "Flips « aussi pour la 2e heure » (A2)."
  def toggle_following(roll), do: Map.update(roll, :record_following, false, &(not &1))

  @doc "Flashes why `record/2` failed."
  def put_error(socket, :forbidden), do: TeacherAssistantWeb.Authz.put_not_allowed(socket)

  def put_error(socket, :unverified),
    do:
      Phoenix.LiveView.put_flash(
        socket,
        :error,
        gettext("École en attente de vérification — enregistrement indisponible.")
      )

  def put_error(socket, :failed),
    do: Phoenix.LiveView.put_flash(socket, :error, gettext("Impossible d'enregistrer l'appel"))

  @doc "« Tous présents »: every student back to present, late minutes cleared."
  def all_present(roll),
    do: %{
      roll
      | marks:
          Map.new(roll.marks, fn
            {id, :sent_home} -> {id, :sent_home}
            {id, _status} -> {id, :present}
          end),
        minutes: Map.new(roll.minutes, fn {id, _minutes} -> {id, nil} end)
    }

  def count(roll, status), do: Enum.count(roll.marks, fn {_id, s} -> s == status end)

  # --- loading -----------------------------------------------------------------

  defp reload(scope, %{course: %CombinedCourse{} = course} = roll) do
    groups = Attendance.combined_period_roll(scope, course, roll.period, roll.date)
    students = Enum.flat_map(groups, & &1.students)
    put_students(roll, students, sent_home(scope, roll, students), groups: groups, flags: %{})
  end

  defp reload(scope, roll) do
    %{students: students} = Attendance.period_roll(scope, roll.cg, roll.period, roll.date)

    put_students(roll, students, sent_home(scope, roll, students),
      groups: nil,
      flags: earlier_absences(scope, roll)
    )
  end

  # --- back-to-back hours (spec audit follow-ups A2) ------------------------------

  # `following`: the periods right after this one with the same lesson (for a
  # combined course, in every member class) whose roll is not taken yet.
  # `prefilled_from`: the period right before, when its roll is taken and this one is
  # not — the roll then starts from it. `record_following`: the « aussi pour la 2e
  # heure » box, on by default.
  defp put_adjacent(%{moved?: true} = roll, _scope),
    do: Map.merge(roll, %{following: [], prefilled_from: nil, record_following: false})

  defp put_adjacent(roll, scope) do
    adjacent =
      Enum.map(
        member_classes(roll),
        &Attendance.adjacent_slots(scope, &1, roll.date, roll.period)
      )

    previous =
      case Enum.map(adjacent, & &1.previous) |> Enum.uniq_by(&(&1 && &1.id)) do
        [%{} = p] -> p
        _ -> nil
      end

    following =
      adjacent
      |> Enum.map(fn %{following: f} -> MapSet.new(f, & &1.id) end)
      |> Enum.reduce(&MapSet.intersection/2)
      |> then(fn ids -> Enum.filter(hd(adjacent).following, &MapSet.member?(ids, &1.id)) end)
      |> Enum.take_while(&(not taken?(scope, roll, &1)))

    prefilled_from =
      if (not roll.taken? and previous) && taken?(scope, roll, previous), do: previous

    roll
    |> then(&if(prefilled_from, do: prefill(scope, &1, prefilled_from), else: &1))
    |> Map.merge(%{
      following: following,
      prefilled_from: prefilled_from,
      record_following: roll.offer_following? and following != []
    })
  end

  defp member_classes(%{groups: [_ | _] = groups}), do: Enum.map(groups, & &1.class_group)
  defp member_classes(%{cg: cg}), do: [cg]

  defp taken?(scope, roll, period) do
    Enum.any?(member_classes(roll), fn cg ->
      %{students: students} = Attendance.period_roll(scope, cg, period, roll.date)
      Enum.any?(students, &(&1.status != nil))
    end)
  end

  # The previous hour's roll, as the start of this one: absences carry over, a late
  # is in the room now (present), minutes start empty. The bursar's send-outs of the
  # day win over the earlier hour: a student sent home since is « renvoyé pour
  # frais » now, one whose send-out was lifted is back — `roll.sent_home` holds
  # today's set for a roll not taken yet (`put_students/4`).
  defp prefill(scope, roll, previous) do
    earlier =
      roll
      |> member_classes()
      |> Enum.flat_map(&Attendance.period_roll(scope, &1, previous, roll.date).students)
      |> Map.new(&{&1.enrollment_id, &1.status})

    marks =
      Map.new(roll.marks, fn {id, _} ->
        status =
          cond do
            MapSet.member?(roll.sent_home, id) -> :sent_home
            Map.get(earlier, id) == :absent -> :absent
            true -> :present
          end

        {id, status}
      end)

    %{roll | marks: marks, minutes: Map.new(roll.minutes, fn {id, _} -> {id, nil} end)}
  end

  # Fees 2: the students the bursar sent home that day.
  defp sent_home(scope, roll, students),
    do: FeeControl.sent_home_ids(scope, Enum.map(students, & &1.enrollment_id), roll.date)

  # A roll not taken yet starts with everyone present, except the students sent home
  # for fees; a roll already taken keeps what the teacher recorded.
  defp put_students(roll, students, sent_home, extra) do
    taken? = Enum.any?(students, &(&1.status != nil))

    default = fn id ->
      if not taken? and MapSet.member?(sent_home, id), do: :sent_home, else: :present
    end

    marks = Map.new(students, &{&1.enrollment_id, &1.status || default.(&1.enrollment_id)})

    Map.merge(roll, %{
      students: Enum.map(students, &Map.take(&1, [:enrollment_id, :student_name])),
      marks: marks,
      # Who this roll treats as sent home: pre-filled now or recorded so.
      sent_home: for({id, :sent_home} <- marks, into: MapSet.new(), do: id),
      minutes: Map.new(students, &{&1.enrollment_id, Map.get(&1, :late_minutes)}),
      taken?: taken?,
      groups: extra[:groups],
      flags: extra[:flags]
    })
  end

  # Students marked absent at an earlier lesson period the same day — the
  # mockup's "absent au créneau précédent" signal. `enrollment_id => [label]`.
  defp earlier_absences(scope, roll) do
    %{periods: periods, students: students} = Attendance.class_register(scope, roll.cg, roll.date)
    earlier = Enum.filter(periods, &(&1.position < roll.period.position))

    Map.new(students, fn s ->
      {s.enrollment_id, for(p <- earlier, s.cells[p.id] == :absent, do: p)}
    end)
  end

  # This hour and the following ones in one transaction: a refused row anywhere
  # saves nothing (each write runs inside the outer transaction).
  defp write_all(scope, roll, marks, [], _following_marks),
    do: write(scope, roll, [roll.period], marks)

  defp write_all(scope, roll, marks, following, following_marks) do
    TeacherAssistant.Repo.transaction(fn ->
      with {:ok, n} <- write(scope, roll, [roll.period], marks),
           {:ok, m} <- write(scope, roll, following, following_marks) do
        n + m
      else
        {:error, reason} -> TeacherAssistant.Repo.rollback(reason)
      end
    end)
  end

  defp write(scope, %{course: %CombinedCourse{} = course} = roll, periods, marks),
    do: Attendance.record_combined_period(scope, course, periods, roll.date, marks)

  defp write(scope, roll, periods, marks),
    do:
      Attendance.record_period(
        scope,
        roll.cg,
        periods,
        roll.teaching_context,
        roll.date,
        marks
      )

  defp fetch_period(scope, period_id) do
    case Enum.find(Attendance.list_periods(scope), &(&1.id == period_id)) do
      nil -> {:error, :not_found}
      period -> {:ok, period}
    end
  end

  defp slot(scope, cg, date, period_id) do
    case Attendance.slot_for(scope, cg, date, period_id) do
      {:ok, slot} -> slot
      {:error, :no_slot} -> nil
    end
  end

  # The teaching context this roll call is recorded under: the placed timetable
  # slot's when one exists, otherwise the signed-in teacher's own assignment on
  # the class (assignment-based roll call). `nil` when neither applies (a
  # conduct manager can still record without one).
  defp resolve_teaching_context(_scope, _cg, %TimetableSlot{teaching_context: ctx}), do: ctx

  defp resolve_teaching_context(scope, cg, nil) do
    case {scope.current_workspace, scope.current_academic_year} do
      {%{}, %{} = year} ->
        scope
        |> Curriculum.list_assignments_for_user(year, scope.current_user)
        |> Enum.find(&(&1.class_group_id == cg.id))

      _ ->
        nil
    end
  end

  # Combined mode: the context belongs to a `CombinedCourse` — one session over
  # the union of the member classes' rosters, each entry still written to the
  # student's own class.
  defp combined_course_for(scope, %TeachingContext{combined_course_id: course_id})
       when not is_nil(course_id) do
    case Curriculum.get_course(scope, course_id) do
      {:ok, course} -> course
      _ -> nil
    end
  end

  defp combined_course_for(_scope, _ctx), do: nil

  # Owning the course, or managing conduct (any class).
  defp authorized?(scope, teaching_context),
    do: owns?(scope, teaching_context) or Discipline.can_manage_conduct?(scope)

  defp owns?(_scope, nil), do: false
  defp owns?(scope, %TeachingContext{teacher_user_id: id}), do: id == scope.current_user.id

  # --- rendering ---------------------------------------------------------------

  @doc """
  The roll-call panel (UX refonte 2026-11-03): an optional eyebrow and title with
  `actions`, the helper line « Tout le monde est présent par défaut… » with « Tous
  présents » (`all_present` event), for a combined course a strip of class chips
  jumping to each class, one row per student — full name and two toggles, Absent
  and Retard (`set` events; tapping the active one puts the student back to
  present), late minutes under a late student — and a footer sticky at the bottom
  of the screen with the counts and the record button (`record` event).
  """
  attr :roll, :map, required: true
  attr :title, :string, default: nil
  attr :eyebrow, :string, default: nil
  slot :actions, doc: "extra header links (« Saisir des notes », close)"

  def roll_panel(assigns) do
    ~H"""
    <div id="roll-panel" class="ta-panel flex flex-col !p-0 shadow-[0_6px_20px_oklch(0%_0_0/0.16)]">
      <div :if={@title} class="flex items-start justify-between gap-2 px-4 pt-4 sm:px-[18px]">
        <div class="min-w-0">
          <p :if={@eyebrow} class="ta-eyebrow">{@eyebrow}</p>
          <h2 class="mt-0.5 text-[1.2rem] font-semibold leading-tight">{@title}</h2>
        </div>
        <div :if={@actions != []} class="flex shrink-0 items-center gap-1">
          {render_slot(@actions)}
        </div>
      </div>

      <nav
        :if={@roll.groups && length(@roll.groups) > 1}
        id="roll-class-chips"
        aria-label={gettext("Aller à une classe")}
        class="flex gap-1.5 overflow-x-auto px-4 pt-3 sm:px-[18px]"
      >
        <a
          :for={group <- @roll.groups}
          id={"roll-class-chip-#{group.class_group.id}"}
          href={"#attendance-class-#{group.class_group.id}"}
          class="flex h-[2.125rem] flex-none items-center gap-1 rounded-full border border-base-content/20 px-3 text-xs font-semibold transition-colors hover:bg-base-content/5"
        >
          {group.class_group.label}
          <span class="ta-num font-medium opacity-85">{length(group.students)}</span>
        </a>
      </nav>

      <p
        :if={@roll[:prefilled_from]}
        id="roll-prefilled"
        class="mx-4 mt-3 rounded-box bg-info/10 px-3 py-2 text-[0.82rem] text-info sm:mx-[18px]"
      >
        <.icon name="hero-arrow-uturn-right" class="mr-1 inline size-4 align-text-bottom" />
        {gettext("Pré-rempli depuis l'heure précédente (%{label}) : qui est parti, qui est revenu ?",
          label: @roll.prefilled_from.label
        )}
      </p>

      <div class="flex items-start justify-between gap-3 px-4 pt-3 sm:px-[18px]">
        <p id="roll-help" class="text-[0.82rem] text-base-content/70">
          {gettext("Tout le monde est présent par défaut. Touchez")}
          <span class="font-semibold text-error">{gettext("Absent")}</span>
          {gettext("ou")} <span class="font-semibold text-warning">{gettext("Retard")}</span>
          {gettext("pour les exceptions.")}
        </p>
        <button
          id="all-present"
          type="button"
          phx-click="all_present"
          class="btn btn-ghost btn-sm min-h-11 shrink-0 gap-1 px-2.5 sm:min-h-0"
        >
          <.icon name="hero-check" class="size-4" /> {gettext("Tous présents")}
        </button>
      </div>

      <div class="pb-1 pt-2">
        <%= if @roll.groups do %>
          <div
            :for={group <- @roll.groups}
            id={"attendance-class-#{group.class_group.id}"}
            class="scroll-mt-20"
          >
            <h3 class="flex min-h-9 items-center gap-2 border-y border-base-300/70 bg-base-200/60 px-4 text-xs font-semibold sm:px-[18px]">
              <span class="flex-1 uppercase tracking-wide text-base-content/70">
                {group.class_group.label} · {ngettext(
                  "%{count} élève",
                  "%{count} élèves",
                  length(group.students)
                )}
              </span>
              <span class="ta-num font-medium text-base-content/70">{group_summary(
                @roll,
                group.students
              )}</span>
            </h3>
            <.roster students={group.students} roll={@roll} />
          </div>
        <% else %>
          <.roster students={@roll.students} roll={@roll} />
        <% end %>
      </div>

      <div
        id="roll-footer"
        class="ta-stickyfoot sticky bottom-0 z-10 flex flex-col gap-2 rounded-b-box border-t border-base-300 bg-base-200/95 px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur sm:flex-row sm:items-center sm:px-[18px]"
      >
        <button
          :if={@roll[:offer_following?] and @roll.following != []}
          id="record-following"
          type="button"
          role="checkbox"
          aria-checked={to_string(@roll.record_following)}
          phx-click="toggle_following"
          class={[
            "flex min-h-10 items-center gap-2 rounded-full border px-3 text-[0.82rem] font-semibold transition-colors",
            if(@roll.record_following,
              do: "border-primary bg-primary/12 text-primary",
              else: "border-base-300 text-base-content/70 hover:bg-base-content/8"
            )
          ]}
        >
          <.icon
            name={if @roll.record_following, do: "hero-check-circle-solid", else: "hero-circle"}
            class="size-5"
          />
          {ngettext(
            "Aussi pour la 2e heure",
            "Aussi pour les %{count} heures suivantes",
            length(@roll.following)
          )}
        </button>
        <div
          id="roll-counts"
          class="ta-num flex flex-wrap gap-x-4 gap-y-1 text-[0.82rem] font-medium sm:flex-1"
        >
          <span>{ngettext("%{count} présent", "%{count} présents", count(@roll, :present))}</span>
          <span class={count(@roll, :absent) > 0 && "text-error"}>
            {ngettext("%{count} absent", "%{count} absents", count(@roll, :absent))}
          </span>
          <span class={count(@roll, :late) > 0 && "text-warning"}>
            {ngettext("%{count} retard", "%{count} retards", count(@roll, :late))}
          </span>
          <span :if={count(@roll, :sent_home) > 0} class="text-info">
            {ngettext(
              "%{count} renvoyé pour frais",
              "%{count} renvoyés pour frais",
              count(@roll, :sent_home)
            )}
          </span>
          <span :if={@roll.taken?} class="flex items-center gap-1 text-success">
            <.icon name="hero-check-circle" class="size-4" />
            {if (@roll[:saved_periods] || 1) > 1,
              do: gettext("Appel enregistré pour %{count} heures.", count: @roll.saved_periods),
              else: gettext("Appel enregistré.")}
          </span>
        </div>
        <button
          id="record-roll"
          type="button"
          phx-click="record"
          phx-disable-with={gettext("Enregistrement…")}
          class={[
            "btn h-12 px-6 text-[0.95rem]",
            if(@roll.taken?, do: "btn-outline", else: "btn-primary")
          ]}
        >
          {if @roll.taken?, do: gettext("Modifier l'appel"), else: gettext("Valider l'appel")}
        </button>
      </div>
    </div>
    """
  end

  # « 1 absent · 1 retard » for one class of a combined roll; « Tous présents » when none.
  defp group_summary(roll, students) do
    statuses = Enum.map(students, &roll.marks[&1.enrollment_id])
    absent = Enum.count(statuses, &(&1 == :absent))
    late = Enum.count(statuses, &(&1 == :late))

    [
      absent > 0 && ngettext("%{count} absent", "%{count} absents", absent),
      late > 0 && ngettext("%{count} retard", "%{count} retards", late)
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> gettext("Tous présents")
      parts -> Enum.join(parts, " · ")
    end
  end

  attr :students, :list, required: true
  attr :roll, :map, required: true

  defp roster(assigns) do
    ~H"""
    <ol class="flex flex-col">
      <li
        :for={{student, n} <- Enum.with_index(@students, 1)}
        id={"student-row-#{student.enrollment_id}"}
        data-status={@roll.marks[student.enrollment_id]}
        class={[
          "ta-row-rule grid grid-cols-[1.4rem_minmax(0,1fr)_auto] items-center gap-x-2.5 px-4 py-2 transition-colors last:border-b-0 sm:px-[18px]",
          row_tint(@roll.marks[student.enrollment_id])
        ]}
      >
        <span class="ta-num text-right text-[0.72rem] text-base-content/70">{n}</span>
        <span class="flex min-w-0 flex-col">
          <span class={[
            "break-words text-[0.95rem] leading-snug",
            @roll.marks[student.enrollment_id] != :present && "font-semibold"
          ]}>
            {student.student_name}
          </span>
          <span
            :if={(@roll.flags[student.enrollment_id] || []) != []}
            class="text-[0.75rem] text-warning"
          >
            {absent_flag(@roll.flags[student.enrollment_id])}
          </span>
        </span>
        <div
          :if={MapSet.member?(@roll.sent_home, student.enrollment_id)}
          class="flex items-center gap-1.5"
        >
          <span
            :if={@roll.marks[student.enrollment_id] == :sent_home}
            id={"sent-home-#{student.enrollment_id}"}
            class="rounded-full bg-info/15 px-2.5 py-1 text-[0.78rem] font-semibold text-info"
          >
            {AttendanceStatus.label(:sent_home)}
          </span>
          <button
            :if={@roll.marks[student.enrollment_id] != :sent_home}
            type="button"
            id={"att-#{student.enrollment_id}-sent_home"}
            phx-click="set"
            phx-value-enrollment_id={student.enrollment_id}
            phx-value-status="sent_home"
            title={gettext("Remettre « Renvoyé pour frais »")}
            class="btn btn-ghost btn-xs h-10 gap-1 text-info"
          >
            <.icon name="hero-arrow-uturn-left" class="size-3.5" /> {AttendanceStatus.label(
              :sent_home
            )}
          </button>
          <button
            type="button"
            id={"att-#{student.enrollment_id}-present"}
            phx-click="set"
            phx-value-enrollment_id={student.enrollment_id}
            phx-value-status="present"
            aria-pressed={to_string(@roll.marks[student.enrollment_id] == :present)}
            title={gettext("Il est en classe : présent")}
            aria-label={gettext("Il est en classe : présent")}
            class={[
              "h-10 rounded-field border px-2.5 text-[0.8rem] font-semibold transition-colors",
              if(@roll.marks[student.enrollment_id] == :present,
                do: "border-success bg-success/20 text-success",
                else: "border-base-300 text-base-content/70 hover:bg-base-content/8"
              )
            ]}
          >
            {AttendanceStatus.label(:present)}
          </button>
        </div>
        <div
          :if={not MapSet.member?(@roll.sent_home, student.enrollment_id)}
          class="flex gap-1.5"
          role="group"
          aria-label={student.student_name}
        >
          <button
            :for={status <- [:absent, :late]}
            type="button"
            id={"att-#{student.enrollment_id}-#{status}"}
            phx-click="set"
            phx-value-enrollment_id={student.enrollment_id}
            phx-value-status={status}
            aria-pressed={to_string(@roll.marks[student.enrollment_id] == status)}
            class={[
              "h-10 cursor-pointer rounded-field border px-2.5 text-[0.8rem] font-semibold transition-colors",
              toggle_class(status, @roll.marks[student.enrollment_id] == status)
            ]}
          >
            {toggle_label(status)}
          </button>
        </div>
        <form
          :if={@roll.marks[student.enrollment_id] == :late}
          id={"late-minutes-form-#{student.enrollment_id}"}
          phx-change="minutes"
          class="col-span-2 col-start-2 flex items-center gap-1.5 pt-1.5"
        >
          <label
            for={"late-minutes-#{student.enrollment_id}"}
            class="text-[0.78rem] text-base-content/70"
          >
            {gettext("Minutes de retard")}
          </label>
          <input
            id={"late-minutes-#{student.enrollment_id}"}
            type="number"
            min="1"
            max="240"
            inputmode="numeric"
            name={"minutes[#{student.enrollment_id}]"}
            value={@roll.minutes[student.enrollment_id]}
            placeholder={gettext("min")}
            class="input input-sm ta-num w-20 text-right"
          />
          <span class="text-[0.78rem] text-base-content/70">{gettext("min")}</span>
        </form>
      </li>
    </ol>
    """
  end

  defp toggle_label(:absent), do: gettext("Absent")
  defp toggle_label(:late), do: gettext("Retard")

  defp row_tint(:absent), do: "bg-error/8"
  defp row_tint(:late), do: "bg-warning/6"
  defp row_tint(_status), do: nil

  defp absent_flag(periods) do
    labels = Enum.map_join(periods, ", ", & &1.label)

    if Enum.all?(periods, &(&1.start_time.hour < 12)),
      do: gettext("Absent en %{periods} — ce matin", periods: labels),
      else: gettext("Absent en %{periods} — aujourd'hui", periods: labels)
  end

  defp toggle_class(:absent, true), do: "border-error bg-error text-error-content"
  defp toggle_class(:late, true), do: "border-warning bg-warning text-warning-content"

  defp toggle_class(_status, false),
    do: "border-base-300 bg-transparent text-base-content/70 hover:bg-base-content/8"
end
