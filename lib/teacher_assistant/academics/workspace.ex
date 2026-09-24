defmodule TeacherAssistant.Academics.Workspace do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Academics.{Period, Reference, SchoolTemplates, Subject}
  alias TeacherAssistant.Accounts.{SchoolMembership, SchoolProfile}

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

  postgres do
    table "workspaces"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name],
      update: [:name]
    ]

    # School creation as a single transactional create: the workspace row is
    # inserted, then its profile, its :head membership and the seeded Subject
    # catalog are created in the same create transaction (an after_action
    # error rolls the whole thing back — no orphan workspace).
    create :create_school do
      accept [:name]
      argument :owner_user_id, :uuid, allow_nil?: false
      argument :profile, :map, default: %{}

      change after_action(fn changeset, workspace, _context ->
               owner_user_id = Ash.Changeset.get_argument(changeset, :owner_user_id)
               profile_input = Ash.Changeset.get_argument(changeset, :profile) || %{}
               profile_attrs = build_profile_attrs(profile_input)

               with {:ok, _profile} <-
                      create_school_profile(workspace, owner_user_id, profile_attrs),
                    {:ok, _membership} <- create_head_membership(workspace, owner_user_id),
                    :ok <-
                      seed_catalog(
                        workspace,
                        Map.get(profile_attrs, :school_type),
                        Map.get(profile_attrs, :subsystem)
                      ),
                    :ok <- seed_periods(workspace) do
                 {:ok, workspace}
               end
             end)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    has_many :school_memberships, TeacherAssistant.Accounts.SchoolMembership do
      destination_attribute :workspace_id
    end
  end

  # --- create_school orchestration helpers (moved from Accounts.Schools) ---

  defp build_profile_attrs(input) do
    Map.merge(
      %{
        school_type: :lycee,
        subsystem: :francophone,
        sector: :public,
        region: :centre,
        town: "—"
      },
      Map.take(input, @profile_keys)
    )
  end

  defp create_school_profile(workspace, owner_user_id, profile_attrs) do
    SchoolProfile
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(profile_attrs, %{workspace_id: workspace.id, owner_user_id: owner_user_id})
    )
    |> Ash.create()
  end

  # `SchoolMembership` isn't multitenant yet (Task 15), but setting the tenant
  # here is harmless — Ash ignores a tenant on a non-multitenant resource —
  # and keeps this call site ready for when it flips.
  defp create_head_membership(workspace, owner_user_id) do
    SchoolMembership
    |> Ash.Changeset.for_create(:create, %{
      workspace_id: workspace.id,
      user_id: owner_user_id,
      roles: [:head]
    })
    |> Ash.Changeset.set_tenant(workspace.id)
    |> Ash.create()
  end

  # The default bell schedule, so roll call works from day one (Increment 2).
  # `Period` is multitenant (attribute strategy); the tenant is set below
  # instead of a `workspace_id` param, which is no longer an acceptable
  # create attribute.
  defp seed_periods(workspace) do
    Reference.default_periods_preset()
    |> Enum.reduce_while(:ok, fn attrs, :ok ->
      case Period
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.Changeset.set_tenant(workspace.id)
           |> Ash.create() do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # `Subject` is multitenant (attribute strategy); the tenant is set below
  # instead of a `workspace_id` param, which is no longer an acceptable
  # create attribute.
  defp seed_catalog(workspace, type, subsystem) do
    SchoolTemplates.subjects_for(type, subsystem)
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {attrs, i}, :ok ->
      params = Map.put(attrs, :position, i)

      case Subject
           |> Ash.Changeset.for_create(:create, params)
           |> Ash.Changeset.set_tenant(workspace.id)
           |> Ash.create() do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
