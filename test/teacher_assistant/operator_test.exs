defmodule TeacherAssistant.OperatorTest do
  use TeacherAssistant.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias TeacherAssistant.{Operator, Organization, Scope, TeacherFixtures}

  setup do
    %{scope: head, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{head: head, ws: ws, op: op}
  end

  test "only the operator may call it", %{head: head} do
    assert_raise Ash.Error.Forbidden, fn -> Operator.overview(head) end
    assert_raise Ash.Error.Forbidden, fn -> Operator.list_schools(head, %{}) end
    assert_raise Ash.Error.Forbidden, fn -> Operator.search_users(head, "a") end
  end

  test "overview counts schools by status", %{op: op, ws: ws} do
    before = Operator.overview(op)
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    assert Operator.overview(op).schools.suspended == before.schools.suspended + 1
    assert before.members >= 1
  end

  describe "overview activity" do
    setup %{head: head} do
      year = head.current_academic_year
      [cg | _] = TeacherAssistant.Enrollment.list_class_groups(head, year)
      {:ok, _} = TeacherAssistant.Enrollment.add_student(head, cg, %{full_name: "Awa", sex: :f})
      [%{enrollment: awa} | _] = TeacherAssistant.Enrollment.list_roster(head, cg)

      {:ok, _} =
        TeacherAssistant.Discipline.add_sanction(head, awa, %{
          type: :avertissement,
          date: Date.utc_today()
        })

      :ok
    end

    test "a school that acted this week is active and set up", %{op: op, ws: ws} do
      o = Operator.overview(op)

      assert o.usage.active_schools == 1
      assert o.usage.active_users == 1
      assert o.funnel == %{signed_up: 1, verified: 1, set_up: 1, active: 1}
      assert [%{id: id, actions_7d: 1, students: 1, status: :verified}] = o.school_rows
      assert id == ws.id
      assert o.schools.total == 1
      assert o.modules[:discipline].used == 1
      assert o.modules[:emploi_du_temps].used == nil
      assert o.attention.quiet == [] and o.attention.silent == []
      assert length(o.weekly) == 12
      assert List.last(o.weekly).actions == 1
      assert o.growth.new_schools == 1
      assert o.growth.new_users >= 1
      assert is_integer(o.system.db_bytes)
    end

    test "a school whose last action is three weeks old is quiet", %{op: op, ws: ws} do
      three_weeks_ago = DateTime.add(DateTime.utc_now(), -21, :day)
      TeacherAssistant.Repo.update_all("sanction_entries", set: [inserted_at: three_weeks_ago])

      o = Operator.overview(op)
      assert [%{id: id}] = o.attention.quiet
      assert id == ws.id
      assert o.usage.active_schools == 0
      assert o.funnel.active == 0
    end
  end

  test "the digest names a school whose first students came in since yesterday", %{
    head: head,
    ws: ws
  } do
    assert Operator.digest().first_steps == []

    [cg | _] = TeacherAssistant.Enrollment.list_class_groups(head, head.current_academic_year)
    {:ok, _} = TeacherAssistant.Enrollment.add_student(head, cg, %{full_name: "Awa", sex: :f})

    assert [%{id: id, name: name, steps: [:students]}] = Operator.digest().first_steps
    assert id == ws.id and name == ws.name

    # an older first student: not a first step any more, even with a new one today
    TeacherAssistant.Repo.update_all("enrollments",
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -3, :day)]
    )

    {:ok, _} = TeacherAssistant.Enrollment.add_student(head, cg, %{full_name: "Bello", sex: :m})
    assert Operator.digest().first_steps == []
  end

  test "a verified school with no activity for a week is listed as silent", %{op: op, ws: ws} do
    week_ago = DateTime.add(DateTime.utc_now(), -8, :day)
    TeacherAssistant.Repo.update_all("workspaces", set: [inserted_at: week_ago])

    assert [%{id: id}] = Operator.overview(op).attention.silent
    assert id == ws.id
  end

  test "an unverified school waits in the queue", %{op: op} do
    %{workspace: pending} = TeacherFixtures.setup_complete_school_fixture(%{verified: false})
    assert [%{id: id, name: _}] = Operator.overview(op).attention.pending
    assert id == pending.id
  end

  test "list_schools filters by name, status, suspension and module", %{op: op, ws: ws} do
    {:ok, ws} = Organization.set_modules(op, ws, [:notes])
    ids = fn rows -> Enum.map(rows, & &1.workspace.id) end

    assert ws.id in ids.(Operator.list_schools(op, %{q: ws.name}))
    assert ws.id in ids.(Operator.list_schools(op, %{status: :verified}))
    refute ws.id in ids.(Operator.list_schools(op, %{status: :unverified}))
    refute ws.id in ids.(Operator.list_schools(op, %{suspended: true}))
    assert ws.id in ids.(Operator.list_schools(op, %{module: :notes}))
    refute ws.id in ids.(Operator.list_schools(op, %{module: :frais}))
  end

  test "every school is a row, the active first, with its activated accounts", %{
    op: op,
    ws: ws,
    head: head
  } do
    %{workspace: pending} = TeacherFixtures.setup_complete_school_fixture(%{verified: false})
    _teacher = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})

    head_id = Ecto.UUID.dump!(head.current_user.id)

    TeacherAssistant.Repo.update_all(
      from(u in "users", where: u.id == ^head_id),
      set: [must_change_password: true]
    )

    rows = Operator.overview(op).school_rows
    assert Enum.map(rows, & &1.id) |> Enum.sort() == Enum.sort([ws.id, pending.id])
    row = Enum.find(rows, &(&1.id == ws.id))
    assert row.members == 2
    assert row.activated == 1
    assert Enum.find(rows, &(&1.id == pending.id)).status == :unverified
  end

  test "get_school returns members and counts", %{op: op, ws: ws, head: head} do
    {:ok, school} = Operator.get_school(op, ws.id)
    assert Enum.any?(school.members, &(&1.user_id == head.current_user.id))
    assert school.counts.classes > 0
    assert school.module_use.discipline == 0
    assert school.module_use.emploi_du_temps == nil
    assert {:error, :not_found} = Operator.get_school(op, Ecto.UUID.generate())
  end

  test "search_users finds by email; an empty query finds nothing", %{op: op, head: head} do
    email = to_string(head.current_user.email)
    assert [%{user: %{id: id}, memberships: [_ | _]}] = Operator.search_users(op, email)
    assert id == head.current_user.id
    assert Operator.search_users(op, "  ") == []
  end

  test "an operator with no school opens the console", %{op: op} do
    assert %{schools: _} = Operator.overview(op)
    assert is_list(Operator.list_schools(op, %{}))
  end
end
