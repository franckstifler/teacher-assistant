defmodule TeacherAssistant.Academics.ProgressionModule do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_modules"
    repo TeacherAssistant.Repo

    references do
      reference :progression_plan, index?: true
      reference :sequence, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :title,
        :position,
        :progression_plan_id,
        :credit_hours,
        :sequence_id,
        :workspace_id
      ],
      update: [:title, :position, :credit_hours, :sequence_id]
    ]

    # System-only: creates the undeletable default bucket. `default?` is never
    # publicly accepted, so a teacher can never mint a second bucket.
    create :create_default_bucket do
      accept [:title, :position, :progression_plan_id, :workspace_id]
      change set_attribute(:default?, true)
    end

    # All modules of a plan, in position order, each with its entries
    # preloaded (also position-sorted). Mirrors the old
    # `Academics.list_progression_modules/1`.
    read :for_plan do
      argument :progression_plan_id, :uuid, allow_nil?: false
      filter expr(progression_plan_id == ^arg(:progression_plan_id))

      prepare fn query, _context ->
        query
        |> Ash.Query.sort(position: :asc)
        |> Ash.Query.load(
          entries: Ash.Query.sort(TeacherAssistant.Academics.ProgressionEntry, position: :asc)
        )
      end
    end

    # Owner-scoped single-module lookup (IDOR guard): the module's plan must
    # belong to the given workspace. Backs `Curriculum.fetch_owned_module/2`.
    read :owned do
      argument :id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and progression_plan.workspace_id == ^arg(:workspace_id))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :default?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :credit_hours, :decimal, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan do
      source_attribute :progression_plan_id
      allow_nil? false
      public? true
    end

    has_many :entries, TeacherAssistant.Academics.ProgressionEntry

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? true
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
