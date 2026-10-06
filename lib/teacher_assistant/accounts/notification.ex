defmodule TeacherAssistant.Accounts.Notification do
  @moduledoc """
  Spec KLM8: one in-app notice to one staff member. The text is not stored: it is
  built at display time from `kind` and `params` (short strings), so it follows the
  reader's language. Rows are written only by `TeacherAssistant.Notifications.deliver/5`;
  the recipient alone reads them and marks them read.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "notifications"
    repo TeacherAssistant.Repo

    custom_indexes do
      # The bell and the inbox: one member's notices, newest first.
      index [:recipient_user_id, :inserted_at]
    end

    references do
      reference :recipient, on_delete: :delete
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    read :inbox do
      pagination offset?: true, countable: true, required?: false, default_limit: 30
      prepare build(sort: [inserted_at: :desc, id: :desc])
    end

    create :deliver do
      accept [:recipient_user_id, :kind, :params, :link]
    end

    update :mark_read do
      change set_attribute(:read_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if expr(recipient_user_id == ^actor(:id))
    end

    policy action(:mark_read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if expr(recipient_user_id == ^actor(:id))
    end

    # Written only by `Notifications.deliver/5`, which bypasses this (`authorize?: false`).
    policy action(:deliver) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, TeacherAssistant.Accounts.NotificationKind,
      allow_nil?: false,
      public?: true

    # Short strings for the text (student, subject, class, …), string keys.
    attribute :params, :map, allow_nil?: false, default: %{}, public?: true
    # An app path, followed when the notice is opened.
    attribute :link, :string, allow_nil?: false, public?: true
    attribute :read_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :recipient, TeacherAssistant.Accounts.User do
      source_attribute :recipient_user_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
