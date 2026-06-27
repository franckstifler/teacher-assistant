defmodule TeacherAssistant.Accounts.User do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    tokens do
      enabled? true
      token_resource TeacherAssistant.Accounts.Token
      signing_secret TeacherAssistant.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password
      end

      magic_link do
        identity_field :email
        registration_enabled? false
        require_interaction? true
        sender TeacherAssistant.Accounts.User.Senders.SendMagicLinkEmail
      end
    end
  end

  postgres do
    table "users"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      get_by :email
    end

    read :sign_in_with_password do
      get? true

      argument :email, :ci_string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string, allow_nil?: false
    end

    read :sign_in_with_token do
      get? true

      argument :token, :string, allow_nil?: false, sensitive?: true
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string, allow_nil?: false
    end

    read :sign_in_with_magic_link do
      get? true

      argument :token, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.MagicLink.SignInPreparation

      metadata :token, :string, allow_nil?: false
    end

    create :create do
      accept [:email, :role, :hashed_password]
    end

    create :register_with_password do
      argument :email, :ci_string, allow_nil?: false

      argument :password, :string,
        allow_nil?: false,
        constraints: [min_length: 8],
        sensitive?: true

      argument :password_confirmation, :string,
        allow_nil?: false,
        constraints: [min_length: 8],
        sensitive?: true

      change set_attribute(:email, arg(:email))
      change AshAuthentication.Strategy.Password.HashPasswordChange
      change AshAuthentication.GenerateTokenChange
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string, allow_nil?: false
    end

    action :request_magic_link do
      argument :email, :ci_string, allow_nil?: false
      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :role, TeacherAssistant.Accounts.UserRole, default: :teacher, public?: true

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end
end
