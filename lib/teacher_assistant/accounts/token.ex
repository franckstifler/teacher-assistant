defmodule TeacherAssistant.Accounts.Token do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read]

    read :expired do
      filter expr(expires_at < now())
    end

    read :get_token do
      get? true
      argument :token, :string, sensitive?: true
      argument :jti, :string, sensitive?: true
      argument :purpose, :string

      prepare AshAuthentication.TokenResource.GetTokenPreparation
    end

    action :revoked?, :boolean do
      argument :token, :string, sensitive?: true
      argument :jti, :string, sensitive?: true

      run AshAuthentication.TokenResource.IsRevoked
    end

    create :revoke_token do
      accept [:extra_data]
      argument :token, :string, allow_nil?: false, sensitive?: true

      change AshAuthentication.TokenResource.RevokeTokenChange
    end

    create :revoke_jti do
      accept [:extra_data]
      argument :subject, :string, allow_nil?: false, sensitive?: true
      argument :jti, :string, allow_nil?: false, sensitive?: true

      change AshAuthentication.TokenResource.RevokeJtiChange
    end

    create :store_token do
      accept [:extra_data, :purpose]
      argument :token, :string, allow_nil?: false, sensitive?: true

      change AshAuthentication.TokenResource.StoreTokenChange
    end

    destroy :expunge_expired do
      change filter expr(expires_at < now())
    end

    update :revoke_all_stored_for_subject do
      accept [:extra_data]
      argument :subject, :string, allow_nil?: false, sensitive?: true

      change AshAuthentication.TokenResource.RevokeAllStoredForSubjectChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    attribute :jti, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      sensitive?: true

    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :extra_data, :map, public?: true

    timestamps()
  end
end
