defmodule TeacherAssistant.NewYear do
  @moduledoc """
  Spec KLM9 (rules 7–11): preparing and starting the next school year. `plan/2` reads
  what the wizard shows; `start/3` builds the new year from it in one transaction —
  calendar, classes, courses, combined courses, form masters, re-enrolments — then
  activates it and closes the old one. Authorization is each write's own policy (admin).
  """
  require Ash.Query

  alias TeacherAssistant.{
    Accounts,
    Assessment,
    Councils,
    Curriculum,
    Enrollment,
    Organization,
    Scope
  }

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ClassGroup,
    CombinedCourse,
    NewYearPlan,
    Reference,
    TeachingContext
  }

  # The resource, not the domain `TeacherAssistant.Enrollment` aliased above.
  alias TeacherAssistant.Academics.Enrollment, as: EnrollmentRecord

  @doc "What the wizard shows for the open `year` (see the moduledoc of `NewYearPlan`)."
  def plan(%Scope{} = scope, %AcademicYear{} = year) do
    classes = Enrollment.list_class_groups(scope, year)

    courses =
      TeachingContext
      |> Ash.Query.filter(academic_year_id == ^year.id and not is_nil(class_group_id))
      |> Ash.read!(scope: scope)

    members = scope |> Accounts.list_members() |> MapSet.new(& &1.user_id)
    councils = Councils.for_period(scope, {:annual, year})
    students = Enum.flat_map(classes, &class_students(scope, &1, year))

    %{
      year: year,
      classes: classes,
      courses: courses,
      members: members,
      students: students,
      default_targets: NewYearPlan.default_targets(classes),
      checks: %{
        open_councils: Enum.reject(classes, &match?(%{status: :held}, councils[&1.id])),
        proposals:
          students |> Enum.filter(&(&1.source == :proposal)) |> Enum.frequencies_by(& &1.class_id),
        departed_courses: Enum.count(courses, &(not MapSet.member?(members, &1.teacher_user_id))),
        before_end?: Date.compare(Reference.today(), year.end_date) == :lt
      }
    }
  end

  @doc "Each student's decision for the year: the annual council's choice, else the engine's proposal."
  def decisions(%Scope{} = scope, %ClassGroup{} = cg, %AcademicYear{} = year) do
    period = {:annual, year}
    council = Councils.council(scope, cg, period)

    passage = %{
      rules: Assessment.passage_rules(scope),
      students: Councils.passage_inputs(scope, cg, period)
    }

    proposed =
      for {student_id, %{proposal: proposal}} when not is_nil(proposal) <-
            Councils.outcomes(
              council,
              Assessment.class_results_for_period(scope, cg, period),
              passage
            ),
          into: %{},
          do: {student_id, {proposal, :proposal}}

    chosen =
      for %{passage_decision: decision, student_id: student_id} when not is_nil(decision) <-
            council.decisions || [],
          into: %{},
          do: {student_id, {decision, :council}}

    Map.merge(proposed, chosen)
  end

  defp class_students(scope, cg, year) do
    decisions = decisions(scope, cg, year)

    for %{student: student, enrollment: enrollment} <- Enrollment.list_roster(scope, cg) do
      {decision, source} = Map.get(decisions, student.id, {nil, nil})

      %{
        student_id: student.id,
        enrollment_id: enrollment.id,
        class_id: cg.id,
        name: student.full_name,
        decision: decision,
        source: source
      }
    end
  end

  @doc """
  Starts the next year from the open `year` (rules 9–10), in one transaction. A class
  missing from `labels` keeps its label; `targets` override the default targets, and a
  target that is not one of the year's classes counts as « Ne pas réinscrire ».
  """
  def start(%Scope{} = scope, %AcademicYear{id: year_id}, attrs) do
    # Checked first: the plan's reads (discipline, attendance) are not all open to
    # every member, and a refused read must not surface as a crash.
    if Organization.can_manage_calendar?(scope),
      do: transact_start(scope, year_id, attrs),
      else: {:error, :forbidden}
  end

  defp transact_start(scope, year_id, attrs) do
    Ash.transact(
      [AcademicYear, ClassGroup, TeachingContext, CombinedCourse, EnrollmentRecord],
      fn ->
        case lock_open(scope, year_id) do
          {:ok, year} -> build(scope, year, attrs)
          # Nothing written yet. Returned as a value: a bare-atom `{:error, _}` would come
          # back from `Ash.transact/2` wrapped in an `Ash.Error.Unknown`.
          {:error, reason} -> {:refused, reason}
        end
      end,
      # A large school copies thousands of rows; Ecto's 15 s default would roll it all back.
      timeout: :timer.minutes(5)
    )
    |> case do
      {:ok, {:ok, new}} -> {:ok, new}
      {:ok, {:refused, reason}} -> {:error, reason}
      {:error, error} -> {:error, error}
    end
  end

  defp build(scope, year, attrs) do
    plan = plan(scope, year)
    targets = targets(plan, Map.get(attrs, :targets, %{}))

    with {:ok, new} <- create_year(scope, attrs),
         :ok <- Organization.build_default_calendar(scope, new),
         {:ok, copies} <- copy_classes(scope, plan, new, Map.get(attrs, :labels, %{})),
         :ok <- copy_courses(scope, plan.courses, copies),
         :ok <- enroll(scope, plan, targets, copies, new),
         {:ok, new} <- Organization.activate_academic_year(scope, new),
         {:ok, _closed} <- Organization.close_academic_year(scope, year) do
      {:ok, new}
    end
  end

  # Read under a row lock: a concurrent start waits, then finds the year closed.
  defp lock_open(scope, id) do
    AcademicYear
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(scope: scope)
    |> case do
      {:ok, %AcademicYear{status: :open} = year} -> {:ok, year}
      {:ok, %AcademicYear{}} -> {:error, :already_closed}
      _ -> {:error, :not_found}
    end
  end

  defp targets(plan, overrides) do
    ids = MapSet.new(plan.classes, & &1.id)

    for {class_id, target} <- overrides,
        MapSet.member?(ids, class_id),
        into: plan.default_targets do
      {class_id, if(MapSet.member?(ids, target), do: target)}
    end
  end

  defp create_year(scope, attrs) do
    Organization.create_academic_year(scope, %{
      name: attrs.name,
      start_date: attrs.start_date,
      end_date: attrs.end_date,
      active: false
    })
  end

  defp copy_classes(scope, plan, new, labels) do
    Enum.reduce_while(plan.classes, {:ok, %{}}, fn cg, {:ok, acc} ->
      label = labels |> Map.get(cg.id, cg.label) |> String.trim()

      with {:ok, copy} <-
             Enrollment.create_class_group(scope, new, %{
               label: label,
               level: cg.level,
               serie: cg.serie,
               subsystem: cg.subsystem
             }),
           {:ok, copy} <- form_master(scope, copy, cg.form_master_user_id, plan.members) do
        {:cont, {:ok, Map.put(acc, cg.id, copy)}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # A form master who left the school is not carried over.
  defp form_master(scope, copy, user_id, members) do
    if user_id && MapSet.member?(members, user_id),
      do: Enrollment.set_form_master(scope, copy, user_id),
      else: {:ok, copy}
  end

  defp copy_courses(scope, courses, copies) do
    with {:ok, new_by_old} <- create_courses(scope, courses, copies) do
      courses
      |> Enum.filter(& &1.combined_course_id)
      |> Enum.group_by(& &1.combined_course_id, &Map.fetch!(new_by_old, &1.id))
      |> Enum.reduce_while(:ok, fn {_old_course, members}, :ok ->
        case Curriculum.combine_course(scope, members) do
          {:ok, _course} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  # Copied as is — a departed teacher's course too (rule 10) — hence the plain create
  # rather than `Curriculum.assign_teacher/4`, which wants an active member.
  defp create_courses(scope, courses, copies) do
    Enum.reduce_while(courses, {:ok, %{}}, fn tc, {:ok, acc} ->
      copy = Map.fetch!(copies, tc.class_group_id)

      TeachingContext
      |> Ash.Changeset.for_create(
        :create,
        %{
          subject: tc.subject,
          subject_id: tc.subject_id,
          level: copy.level,
          serie: copy.serie,
          subsystem: copy.subsystem,
          weekly_hours: tc.weekly_hours,
          coefficient: tc.coefficient,
          teacher_user_id: tc.teacher_user_id,
          class_group_id: copy.id,
          academic_year_id: copy.academic_year_id
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, new_tc} -> {:cont, {:ok, Map.put(acc, tc.id, new_tc)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp enroll(scope, plan, targets, copies, new) do
    plan.students
    |> NewYearPlan.placements(targets)
    |> Enum.filter(& &1.to)
    |> Enum.reduce_while(:ok, fn placed, :ok ->
      EnrollmentRecord
      |> Ash.Changeset.for_create(
        :create,
        %{
          student_id: placed.student_id,
          class_group_id: Map.fetch!(copies, placed.to).id,
          academic_year_id: new.id,
          status: :reinscription,
          repeater: placed.repeater?
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, _enrollment} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
