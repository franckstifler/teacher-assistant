defmodule TeacherAssistant.Academics.TeacherProfileTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.{TeacherFixtures, Timetabling}
  alias TeacherAssistant.Academics.TeacherProfile

  setup do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Profile school"
      })

    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = school_scope(user, school)
    member = Enum.find(Accounts.list_members(scope), &(&1.user_id == user.id))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    %{scope: scope, member: member, a: a, b: b, year: year}
  end

  test "combines shared classes and counts scheduled lessons once", c do
    {:ok, ta} =
      Curriculum.assign_teacher(c.scope, c.a, c.member.user, %{subject: "Maths", weekly_hours: 4})

    {:ok, tb} =
      Curriculum.assign_teacher(c.scope, c.b, c.member.user, %{subject: "Maths", weekly_hours: 4})

    {:ok, course} = Curriculum.combine_course(c.scope, [ta, tb])
    :ok = Attendance.build_default_periods(c.scope)
    p = Enum.find(Attendance.list_periods(c.scope), &(&1.kind == :lesson))
    {:ok, _} = Timetabling.place_combined_slot(c.scope, course, :monday, p.id)
    assert {:ok, profile} = TeacherProfile.load(c.scope, c.member)
    assert [%{classes: [_, _], hours: 4, scheduled: 1, missing: 3}] = profile.assignments
    assert profile.service.load == 4
    assert profile.scheduled == 1
    assert profile.missing == 3
    assert [%{members: [_, _]}] = profile.lessons.monday
  end

  test "form-master duties do not require a subject assignment", c do
    {:ok, _} = Enrollment.set_form_master(c.scope, c.b, c.member.user_id)
    assert {:ok, p} = TeacherProfile.load(c.scope, c.member)
    assert p.assignments == []
    assert Enum.map(p.form_classes, & &1.id) == [c.b.id]
    assert p.teaching?
  end

  test "missing year is explicit", c do
    assert {:error, :no_year} =
             TeacherProfile.load(%{c.scope | current_academic_year: nil}, c.member)
  end

  test "foreign memberships and ordinary teachers cannot read a profile", c do
    foreign = %{c.member | workspace_id: Ash.UUID.generate()}
    assert {:error, :forbidden} = TeacherProfile.load(c.scope, foreign)
    teacher_scope = TeacherFixtures.member_scope_fixture(c.scope, %{roles: [:teacher]})
    assert {:error, :forbidden} = TeacherProfile.load(teacher_scope, c.member)
  end

  test "selected academic year isolates assignments and form-master classes", c do
    {:ok, _} = Curriculum.assign_teacher(c.scope, c.a, c.member.user, %{subject: "Maths"})
    {:ok, _} = Enrollment.set_form_master(c.scope, c.b, c.member.user_id)

    {:ok, year} =
      Organization.create_academic_year(c.scope, %{
        name: "2026-2027",
        start_date: ~D[2026-09-08],
        end_date: ~D[2027-07-31]
      })

    assert {:ok, p} = TeacherProfile.load(%{c.scope | current_academic_year: year}, c.member)
    assert p.assignments == []
    assert p.form_classes == []
    assert p.scheduled == 0
  end

  test "overscheduled subjects do not cancel missing periods elsewhere", c do
    {:ok, ta} =
      Curriculum.assign_teacher(c.scope, c.a, c.member.user, %{subject: "Maths", weekly_hours: 1})

    {:ok, _} =
      Curriculum.assign_teacher(c.scope, c.b, c.member.user, %{
        subject: "Physics",
        weekly_hours: 1
      })

    :ok = Attendance.build_default_periods(c.scope)
    p = Enum.find(Attendance.list_periods(c.scope), &(&1.kind == :lesson))

    for day <- [:monday, :tuesday] do
      {:ok, _} =
        Timetabling.place_slot(c.scope, c.a, %{
          day: day,
          period_id: p.id,
          teaching_context_id: ta.id
        })
    end

    assert {:ok, profile} = TeacherProfile.load(c.scope, c.member)
    assert profile.service.load == 2
    assert profile.scheduled == 2
    assert profile.missing == 1
  end

  test "disabled timetable module still allows assignment overview", c do
    {:ok, _} = Curriculum.assign_teacher(c.scope, c.a, c.member.user, %{subject: "Maths"})
    scope = %{c.scope | current_workspace: %{c.scope.current_workspace | modules: []}}
    assert {:ok, profile} = TeacherProfile.load(scope, c.member)
    assert length(profile.assignments) == 1
    refute profile.timetable?
    assert profile.days == []
  end
end
