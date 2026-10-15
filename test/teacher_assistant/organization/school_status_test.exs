defmodule TeacherAssistant.Organization.SchoolStatusTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Organization, Scope, TeacherFixtures}

  setup do
    %{workspace: ws, scope: head} = TeacherFixtures.school_fixture()
    operator = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{ws: ws, head: head, operator: operator}
  end

  test "the operator sets modules and the change is journaled", %{ws: ws, operator: op} do
    {:ok, ws} = Organization.set_modules(op, ws, [:notes, :photos])
    assert ws.modules == [:notes, :photos]

    assert [%{action: :modules_changed, details: %{"after" => ["notes", "photos"]}}] =
             Accounts.list_audit_events(op, workspace_id: ws.id)
  end

  test "an unknown module is refused", %{ws: ws, operator: op} do
    assert {:error, _} = Organization.set_modules(op, ws, [:notes, :bogus])
  end

  test "a head cannot change modules, suspend or reactivate", %{ws: ws, head: head} do
    assert_forbidden(Organization.set_modules(head, ws, []))
    assert_forbidden(Organization.suspend_school(head, ws, "x"))
    assert_forbidden(Organization.reactivate_school(head, ws))
  end

  test "suspend needs a reason; reactivate clears it", %{ws: ws, operator: op} do
    assert {:error, _} = Organization.suspend_school(op, ws, "  ")
    {:ok, ws} = Organization.suspend_school(op, ws, "Impayé")
    assert ws.suspended_at && ws.suspension_reason == "Impayé"
    {:ok, ws} = Organization.reactivate_school(op, ws)
    assert ws.suspended_at == nil and ws.suspension_reason == nil

    assert [:school_reactivated, :school_suspended] =
             op |> Accounts.list_audit_events(workspace_id: ws.id) |> Enum.map(& &1.action)
  end

  test "the scope answers module? and suspended?", %{ws: ws, head: head, operator: op} do
    {:ok, _} = Organization.set_modules(op, ws, [:appel])
    scope = school_scope(head.current_user, ws)
    assert Scope.module?(scope, :appel)
    refute Scope.module?(scope, :notes)
    refute Scope.suspended?(scope)
    assert Scope.module?(%Scope{}, :notes)
  end

  test "create_school stores the configured default and ignores a modules attribute" do
    user = TeacherFixtures.user_fixture()

    assert {:ok, ws} =
             Organization.create_school(%Scope{current_user: user}, %{name: "X", modules: []})

    assert ws.modules == TeacherAssistant.Modules.new_school_default()
  end

  test "verifying a school is journaled", %{head: head, operator: op, ws: ws} do
    TeacherFixtures.verify_school!(head)

    assert [%{action: :school_verified}] =
             Accounts.list_audit_events(op, workspace_id: ws.id, action: :school_verified)
  end
end
