defmodule TeacherAssistant.Organization do
  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, User}

  @profile_keys [
    :short_name,
    :school_type,
    :subsystem,
    :sector,
    :region,
    :department,
    :town,
    :phone,
    :email,
    :address,
    :head_name,
    :motto,
    :registration_number
  ]

  authorization do
    authorize :when_requested
  end

  resources do
    resource Workspace do
      define :rename_school, action: :update, args: [:name]
    end

    resource TeacherAssistant.Academics.AcademicYear
    resource TeacherAssistant.Academics.Term
    resource TeacherAssistant.Academics.Sequence
  end

  @doc """
  Creates a school workspace with its profile, the creator's `:head`
  membership, and the seeded Subject catalog — all inside the
  `Workspace.:create_school` create transaction.
  """
  def create_school(%User{} = user, %{} = attrs) do
    name = attrs[:name] || attrs["name"]

    Workspace
    |> Ash.Changeset.for_create(:create_school, %{
      name: name,
      owner_user_id: user.id,
      profile: Map.take(attrs, @profile_keys)
    })
    |> Ash.create()
  end

  @doc """
  The user's personal workspace followed by every school they are an active
  member of.
  """
  def list_workspaces_for(%User{} = user) do
    personal = TeacherAssistant.Academics.ensure_personal_workspace!(user)

    schools =
      SchoolMembership
      |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
      |> Ash.read!()
      |> Enum.map(& &1.workspace)

    [personal | schools]
  end
end
