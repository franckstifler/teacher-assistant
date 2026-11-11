defmodule TeacherAssistant.Accounts.AuditEvent do
  @moduledoc """
  The operator journal (operator console spec §4): one append-only row per operator
  action and per password reset. Not multitenant — operator events span schools.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "audit_events"
    repo TeacherAssistant.Repo

    references do
      reference :actor, on_delete: :nilify
      reference :target_user, on_delete: :nilify
      reference :workspace, on_delete: :delete
    end

    custom_indexes do
      index [:inserted_at]
      index [:workspace_id, :inserted_at]
    end
  end

  actions do
    # Internal only: written by `AuditEvent.Record` with `authorize?: false`; no
    # policy covers it, so no actor can call it.
    create :record do
      accept [
        :actor_user_id,
        :operator_user_id,
        :action,
        :workspace_id,
        :target_user_id,
        :details
      ]
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :action, TeacherAssistant.Accounts.AuditEvent.Action,
      allow_nil?: false,
      public?: true

    attribute :details, :map, allow_nil?: false, default: %{}, public?: true
    # The operator acting as the member (A6); the operator's own journal rows leave it nil.
    attribute :operator_user_id, :uuid, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :actor, TeacherAssistant.Accounts.User do
      source_attribute :actor_user_id
      public? true
    end

    belongs_to :target_user, TeacherAssistant.Accounts.User do
      source_attribute :target_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      public? true
    end
  end
end
