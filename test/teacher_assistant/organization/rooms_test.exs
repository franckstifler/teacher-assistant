defmodule TeacherAssistant.Organization.RoomsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year, head_user: head} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    %{scope: scope, year: year, cg: cg, head: head}
  end

  defp room!(scope, attrs) do
    {:ok, room} = Organization.create_room(scope, Map.merge(%{kind: :classroom}, attrs))
    room
  end

  test "a room is created, listed by name, unique per school regardless of case", %{scope: scope} do
    assert {:ok, labo} =
             Organization.create_room(scope, %{name: "Labo SVT", kind: :laboratory, capacity: 40})

    assert labo.kind == :laboratory and labo.capacity == 40 and labo.active?
    room!(scope, %{name: "salle info", kind: :computer_room})

    assert Enum.map(Organization.list_rooms(scope), & &1.name) == ["Labo SVT", "salle info"]
    assert {:error, _} = Organization.create_room(scope, %{name: " labo svt ", kind: :other})
  end

  test "capacity must be at least 1 and the name not blank", %{scope: scope} do
    assert {:error, _} = Organization.create_room(scope, %{name: "A", capacity: 0})
    assert {:error, _} = Organization.create_room(scope, %{name: "  "})
    assert {:ok, %{capacity: nil}} = Organization.create_room(scope, %{name: "B12"})
  end

  test "list_active_rooms leaves out a deactivated room", %{scope: scope} do
    a = room!(scope, %{name: "A1"})
    room!(scope, %{name: "A2"})
    {:ok, _} = Organization.update_room(scope, a, %{active?: false})
    assert Enum.map(Organization.list_active_rooms(scope), & &1.name) == ["A2"]
  end

  test "a teacher can read rooms but not create one", %{scope: scope} do
    room!(scope, %{name: "B12"})
    teacher = TeacherFixtures.member_scope_fixture(scope)
    assert [_] = Organization.list_rooms(teacher)

    assert {:error, %Ash.Error.Forbidden{}} =
             Organization.create_room(teacher, %{name: "B13", kind: :classroom})
  end

  test "delete is refused while a class, a subject or a slot uses the room", ctx do
    %{scope: scope, cg: cg, head: head} = ctx
    room = room!(scope, %{name: "B12"})

    {:ok, cg} = Enrollment.set_home_room(scope, cg, room.id)
    assert Organization.room_in_use?(scope, room)
    assert {:error, :in_use} = Organization.delete_room(scope, room)
    {:ok, _} = Enrollment.set_home_room(scope, cg, nil)

    [subject | _] = Curriculum.list_subjects(scope)
    {:ok, subject} = Curriculum.update_subject(scope, subject, %{default_room_id: room.id})
    assert {:error, :in_use} = Organization.delete_room(scope, room)
    {:ok, _} = Curriculum.update_subject(scope, subject, %{default_room_id: nil})

    :ok = Attendance.build_default_periods(scope)
    [p | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    {:ok, slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p.id,
        teaching_context_id: tc.id
      })

    {:ok, slot} =
      slot |> Ash.Changeset.for_update(:update, %{room_id: room.id}, scope: scope) |> Ash.update()

    assert {:error, :in_use} = Organization.delete_room(scope, room)
    :ok = Ash.destroy(slot, scope: scope)

    refute Organization.room_in_use?(scope, room)
    assert :ok = Organization.delete_room(scope, room)
    assert Organization.list_rooms(scope) == []
  end

  test "a class's home room and a subject's default room are set and cleared", ctx do
    %{scope: scope, cg: cg} = ctx
    room = room!(scope, %{name: "Salle info", kind: :computer_room})

    assert {:ok, %{home_room_id: id}} = Enrollment.set_home_room(scope, cg, room.id)
    assert id == room.id

    [subject | _] = Curriculum.list_subjects(scope)

    assert {:ok, %{default_room_id: ^id}} =
             Curriculum.update_subject(scope, subject, %{default_room_id: room.id})
  end

  test "a room of another school cannot be a home room", %{scope: scope, cg: cg} do
    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    foreign = room!(other, %{name: "Ailleurs"})
    assert {:error, _} = Enrollment.set_home_room(scope, cg, foreign.id)
  end

  test "class_sizes counts enrollments per class", %{scope: scope, year: year, cg: cg} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa A", sex: :f})
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Bel B", sex: :m})
    assert Enrollment.class_sizes(scope, year)[cg.id] == 2
  end

  test "set_home_room refuses an inactive room", %{scope: scope, cg: cg} do
    room = room!(scope, %{name: "Vieille salle"})
    {:ok, _} = Organization.update_room(scope, room, %{active?: false})
    assert {:error, :invalid} = Enrollment.set_home_room(scope, cg, room.id)
    assert {:ok, %{home_room_id: nil}} = Enrollment.set_home_room(scope, cg, nil)
  end

  test "rooms_in_use lists every room a class, a subject or a lesson uses", ctx do
    %{scope: scope, cg: cg} = ctx
    home = room!(scope, %{name: "B12"})
    default = room!(scope, %{name: "Salle info"})
    free = room!(scope, %{name: "B13"})
    {:ok, _} = Enrollment.set_home_room(scope, cg, home.id)
    [subject | _] = Curriculum.list_subjects(scope)
    {:ok, _} = Curriculum.update_subject(scope, subject, %{default_room_id: default.id})

    used = Organization.rooms_in_use(scope)
    assert MapSet.member?(used, home.id) and MapSet.member?(used, default.id)
    refute MapSet.member?(used, free.id)
  end
end
