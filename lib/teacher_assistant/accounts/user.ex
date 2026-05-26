defmodule TeacherAssistant.Accounts.User do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

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
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    read :sign_in_with_password do
      description "Attempt to sign in using an email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_magic_link do
      description "Sign in a user with magic link."
      get? true

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      prepare AshAuthentication.Strategy.MagicLink.SignInPreparation

      metadata :token, :string do
        allow_nil? false
      end
    end

    create :create do
      accept [:email, :role, :hashed_password]
    end

    create :register_with_password do
      description "Register a new user with an email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user again, in plain text."
        allow_nil? false
        sensitive? true
      end

      change set_attribute(:email, arg(:email))
      change AshAuthentication.Strategy.Password.HashPasswordChange
      change AshAuthentication.GenerateTokenChange
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass action(:read) do
      authorize_if always()
    end

    bypass action(:create) do
      # TODO: Update this policy
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :role, TeacherAssistant.Accounts.UserRole, default: :teacher, public?: true

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    # attribute :full_name, :string, allow_nil?: false, public?: true
  end

  relationships do
    has_many :school_memberships, TeacherAssistant.Accounts.UserSchool
  end

  identities do
    identity :unique_email, [:email]
  end
end
