defmodule TeacherAssistant.Academics.EnrollmentDepartureTest do
  @moduledoc "A student who leaves keeps their history (spec audit follow-ups A7)."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
    {:ok, %{enrollment: awa}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, %{enrollment: bob}} = Enrollment.enroll_new(scope, cg, %{full_name: "Bilal", sex: :m})
    %{scope: scope, year: year, cg: cg, awa: awa, bob: bob}
  end

  defp names(rows), do: rows |> Enum.map(& &1.student.full_name) |> Enum.sort()

  test "leave stamps today, the reason and the note; the status is untouched", ctx do
    {:ok, e} =
      Enrollment.leave(ctx.scope, ctx.awa, %{
        departure_reason: :transfer,
        departure_note: "Lycée de Mbalmayo"
      })

    assert e.left_on == Reference.today()
    assert e.departure_reason == :transfer
    assert e.departure_note == "Lycée de Mbalmayo"
    assert e.status == :inscription
  end

  test "the departure day lies within the enrollment's year and not after today (review)", ctx do
    today = Reference.today()

    assert {:error, %Ash.Error.Invalid{}} =
             Enrollment.leave(ctx.scope, ctx.awa, %{
               departure_reason: :transfer,
               left_on: Date.add(today, 1)
             })

    assert {:error, %Ash.Error.Invalid{}} =
             Enrollment.leave(ctx.scope, ctx.awa, %{
               departure_reason: :transfer,
               left_on: Date.add(ctx.year.start_date, -1)
             })

    assert {:ok, _} =
             Enrollment.leave(ctx.scope, ctx.awa, %{
               departure_reason: :transfer,
               left_on: ctx.year.start_date
             })
  end

  test "a departed student is out of today's roster and in yesterday's", ctx do
    today = Reference.today()
    {:ok, _} = Enrollment.leave(ctx.scope, ctx.awa, %{departure_reason: :dropout})

    assert names(Enrollment.list_roster(ctx.scope, ctx.cg)) == ["Bilal"]

    assert names(Enrollment.list_roster(ctx.scope, ctx.cg, on: Date.add(today, -1))) == [
             "Awa",
             "Bilal"
           ]

    assert names(Enrollment.list_roster(ctx.scope, ctx.cg, on: :all)) == ["Awa", "Bilal"]
    assert ctx.scope |> Enrollment.list_students(ctx.cg) |> Enum.map(& &1.full_name) == ["Bilal"]
  end

  test "leave is refused twice, and refused to a form master", ctx do
    {:ok, e} = Enrollment.leave(ctx.scope, ctx.awa, %{departure_reason: :other})
    assert {:error, _} = Enrollment.leave(ctx.scope, e, %{departure_reason: :other})

    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)
    assert_forbidden(Enrollment.leave(fm, ctx.bob, %{departure_reason: :other}))
  end

  test "a reason is required", ctx do
    assert {:error, _} = Enrollment.leave(ctx.scope, ctx.awa, %{})
  end

  test "return clears the departure; re-enrolling in the same year is refused", ctx do
    {:ok, e} = Enrollment.leave(ctx.scope, ctx.awa, %{departure_reason: :transfer})
    {:ok, student} = Enrollment.fetch_owned_student(ctx.scope, e.student_id)
    assert {:error, :already_enrolled} = Enrollment.enroll_existing(ctx.scope, ctx.cg, student)

    {:ok, back} = Enrollment.return(ctx.scope, e)
    assert {back.left_on, back.departure_reason, back.departure_note} == {nil, nil, nil}
    assert names(Enrollment.list_roster(ctx.scope, ctx.cg)) == ["Awa", "Bilal"]
    assert {:error, _} = Enrollment.return(ctx.scope, back)
  end

  test "remove_mistaken deletes an enrollment without history and names the blocker otherwise",
       ctx do
    assert :ok = Enrollment.remove_mistaken(ctx.scope, ctx.bob)
    assert names(Enrollment.list_roster(ctx.scope, ctx.cg, on: :all)) == ["Awa"]

    [seq | _] = Organization.list_sequences(ctx.scope, ctx.year)

    {:ok, _} =
      Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: seq.start_date})

    assert {:error, :sanctions} = Enrollment.remove_mistaken(ctx.scope, ctx.awa)
  end

  test "an attendance entry blocks a mistaken removal", ctx do
    :ok = Attendance.build_default_periods(ctx.scope)
    period = ctx.scope |> Attendance.list_periods() |> Enum.find(&(&1.kind == :lesson))

    {:ok, _} =
      TeacherAssistant.Academics.AttendanceEntry
      |> Ash.Changeset.for_create(
        :create,
        %{
          enrollment_id: ctx.awa.id,
          period_id: period.id,
          date: Reference.today(),
          status: :absent
        },
        scope: ctx.scope
      )
      |> Ash.create()

    assert {:error, :attendance} = Enrollment.remove_mistaken(ctx.scope, ctx.awa)
  end

  defp attendance_entry!(ctx, enrollment_id) do
    :ok = Attendance.build_default_periods(ctx.scope)
    period = ctx.scope |> Attendance.list_periods() |> Enum.find(&(&1.kind == :lesson))

    {:ok, _} =
      TeacherAssistant.Academics.AttendanceEntry
      |> Ash.Changeset.for_create(
        :create,
        %{
          enrollment_id: enrollment_id,
          period_id: period.id,
          date: Reference.today(),
          status: :absent
        },
        scope: ctx.scope
      )
      |> Ash.create()
  end

  test "another enrollment's history does not block removing a mistaken one (minors)", ctx do
    {:ok, past} =
      Organization.create_academic_year(ctx.scope, %{
        name: "2023-2024",
        start_date: ~D[2023-09-04],
        end_date: ~D[2024-07-31],
        active: false
      })

    {:ok, old_cg} = Enrollment.create_class_group(ctx.scope, past, %{label: "CM2", level: "6ème"})

    {:ok, %{enrollment: old, student: zang}} =
      Enrollment.enroll_new(ctx.scope, old_cg, %{full_name: "Zang", sex: :f})

    attendance_entry!(ctx, old.id)
    {:ok, this_year} = Enrollment.enroll_existing(ctx.scope, ctx.cg, zang)

    assert :ok = Enrollment.remove_mistaken(ctx.scope, this_year)
    assert {:error, :attendance} = Enrollment.remove_mistaken(ctx.scope, old)
  end

  test "a conduct mark blocks a mistaken removal (minors)", ctx do
    [seq | _] = Organization.list_sequences(ctx.scope, ctx.year)
    {:ok, _} = Discipline.set_conduct_marks(ctx.scope, ctx.cg, seq, %{ctx.awa.id => "15"})
    assert {:error, :conduct} = Enrollment.remove_mistaken(ctx.scope, ctx.awa)
  end

  test "enrollments_with_history names the class's enrollments that have any (minors)", ctx do
    attendance_entry!(ctx, ctx.awa.id)

    assert Enrollment.enrollments_with_history(ctx.scope, [ctx.awa.id, ctx.bob.id]) ==
             MapSet.new([ctx.awa.id])
  end

  test "enrollment_count counts current students only", ctx do
    {:ok, _} = Enrollment.leave(ctx.scope, ctx.awa, %{departure_reason: :dropout})

    [cg] =
      Enrollment.list_class_groups(ctx.scope, ctx.year, load: [:enrollment_count])
      |> Enum.filter(&(&1.id == ctx.cg.id))

    assert cg.enrollment_count == 1
  end

  test "the Élèves list hides departed students unless departed: true; counts follow", ctx do
    {:ok, _} = Enrollment.leave(ctx.scope, ctx.awa, %{departure_reason: :dropout})
    page = Enrollment.list_school_students(ctx.scope, ctx.year, class_group_id: ctx.cg.id)
    assert Enum.map(page.results, & &1.student.full_name) == ["Bilal"]

    page = Enrollment.list_school_students(ctx.scope, ctx.year, departed: true)
    assert Enum.map(page.results, & &1.student.full_name) == ["Awa"]
    assert %{departed: 1} = Enrollment.student_counts(ctx.scope, ctx.year)
  end

  test "a closed year refuses leave and return", ctx do
    TeacherFixtures.close_year!(ctx.scope, ctx.year)
    assert {:error, _} = Enrollment.leave(ctx.scope, ctx.awa, %{departure_reason: :other})
  end
end
