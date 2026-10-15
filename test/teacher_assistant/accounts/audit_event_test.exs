defmodule TeacherAssistant.Accounts.AuditEventTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Scope, TeacherFixtures}
  alias TeacherAssistant.Accounts.AuditEvent

  test "an operator reads events newest first, filtered by school and action" do
    operator = TeacherFixtures.admin_user_fixture()
    %{workspace: ws} = TeacherFixtures.school_fixture()

    for action <- [:school_verified, :modules_changed] do
      AuditEvent
      |> Ash.Changeset.for_create(:record, %{
        actor_user_id: operator.id,
        action: action,
        workspace_id: ws.id,
        details: %{"n" => 1}
      })
      |> Ash.create!(authorize?: false)
    end

    scope = %Scope{current_user: operator}

    assert [%{action: :modules_changed}, %{action: :school_verified}] =
             Accounts.list_audit_events(scope, workspace_id: ws.id)

    assert [%{action: :school_verified}] =
             Accounts.list_audit_events(scope, workspace_id: ws.id, action: :school_verified)
  end

  test "nobody but the operator reads the journal" do
    %{scope: head_scope, workspace: ws} = TeacherFixtures.school_fixture()

    AuditEvent
    |> Ash.Changeset.for_create(:record, %{action: :school_verified, workspace_id: ws.id})
    |> Ash.create!(authorize?: false)

    assert Accounts.list_audit_events(head_scope, workspace_id: ws.id) == []
  end

  test "events cannot be changed or deleted" do
    refute Ash.Resource.Info.action(AuditEvent, :update)
    refute Ash.Resource.Info.action(AuditEvent, :destroy)
  end
end
