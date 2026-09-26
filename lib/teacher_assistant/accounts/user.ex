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

        resettable do
          sender TeacherAssistant.Accounts.User.Senders.SendPasswordResetEmail
        end
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
      accept [:email, :hashed_password]
    end

    create :register_with_password do
      accept [:name]

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

    update :promote_to_admin do
      accept []
      change set_attribute(:role, :admin)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Self, co-members of one of the actor's schools, and the operator (who
    # needs owners' emails for the school list).
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)

      authorize_if expr(
                     exists(
                       school_memberships,
                       active == true and
                         exists(
                           workspace.school_memberships,
                           user_id == ^actor(:id) and active == true
                         )
                     )
                   )
    end

    policy action(:promote_to_admin) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :role, TeacherAssistant.Accounts.UserRole, default: :teacher, public?: true
    attribute :name, :string, allow_nil?: true, public?: true

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    timestamps()
  end

  relationships do
    has_many :school_memberships, TeacherAssistant.Accounts.SchoolMembership do
      destination_attribute :user_id
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
