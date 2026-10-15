defmodule TeacherAssistant.OperatorTest do
  use TeacherAssistant.DataCase, async: true

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

  test "get_school returns members and counts", %{op: op, ws: ws, head: head} do
    {:ok, school} = Operator.get_school(op, ws.id)
    assert Enum.any?(school.members, &(&1.user_id == head.current_user.id))
    assert school.counts.classes > 0
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
