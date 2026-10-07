defmodule TeacherAssistant.Accounts.User do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  alias TeacherAssistant.Accounts.Phone

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

      # Accounts created by a school (spec 2026-10-07): the phone number is the
      # identifier, the password is shared with the email strategy. No
      # self-registration and no self-service reset — the school resets it.
      password :phone do
        identity_field :phone
        hashed_password_field :hashed_password
        registration_enabled? false
        sign_in_action_name :sign_in_with_phone
        sign_in_with_token_action_name :sign_in_with_phone_token
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

    read :sign_in_with_phone do
      get? true

      argument :phone, TeacherAssistant.Accounts.Phone, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string, allow_nil?: false
    end

    read :sign_in_with_phone_token do
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
      accept [:email, :phone, :hashed_password]
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

    create :create_by_school do
      accept [:name, :phone, :created_in_workspace_id]
      validate present([:name, :phone, :created_in_workspace_id])
      change TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword
    end

    update :reset_temporary_password do
      accept []
      require_atomic? false
      change TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword
    end

    update :set_own_password do
      accept []
      require_atomic? false

      argument :password, :string,
        allow_nil?: false,
        sensitive?: true,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, allow_nil?: false, sensitive?: true

      validate confirm(:password, :password_confirmation)
      change TeacherAssistant.Accounts.User.Changes.SetOwnPassword
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

    policy action(:create_by_school) do
      authorize_if TeacherAssistant.Accounts.Checks.HeadOfCreatingSchool
    end

    # Never an operator's account; only the school that created the account.
    policy action(:reset_temporary_password) do
      forbid_if expr(role == :admin)
      authorize_if TeacherAssistant.Accounts.Checks.HeadOfCreatingSchool
    end

    policy action(:set_own_password) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:promote_to_admin) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  validations do
    validate present([:email, :phone], at_least: 1), on: [:create]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string, allow_nil?: true, public?: true
    attribute :phone, TeacherAssistant.Accounts.Phone, allow_nil?: true, public?: true
    attribute :role, TeacherAssistant.Accounts.UserRole, default: :teacher, public?: true
    attribute :name, :string, allow_nil?: true, public?: true

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    # Set while the account holds a temporary password given by the school.
    attribute :must_change_password, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :temporary_password_expires_at, :utc_datetime, public?: true

    timestamps()
  end

  relationships do
    has_many :school_memberships, TeacherAssistant.Accounts.SchoolMembership do
      destination_attribute :user_id
      public? true
    end

    # The school whose staff manager created this account (phone accounts);
    # only that school may reset its password. Nil for self-registered users.
    belongs_to :created_in_workspace, TeacherAssistant.Academics.Workspace do
      allow_nil? true
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_phone, [:phone]
  end

  @doc "How to name a person in the UI: name, else email, else formatted phone."
  def display_name(%{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%{email: email}) when not is_nil(email), do: to_string(email)
  def display_name(%{phone: phone}) when is_binary(phone), do: Phone.format(phone)
  def display_name(_user), do: ""

  @doc "How to reach a person: email, else formatted phone, else nil."
  def contact(%{email: email}) when not is_nil(email), do: to_string(email)
  def contact(%{phone: phone}) when is_binary(phone), do: Phone.format(phone)
  def contact(_user), do: nil
end
