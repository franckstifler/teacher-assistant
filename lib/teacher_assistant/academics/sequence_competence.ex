defmodule TeacherAssistant.Academics.SequenceCompetence do
  @moduledoc """
  Spec bulletin v2 §4.3: the competence a course evaluated in one séquence (APC report
  cards), one line written by the teacher and printed on every student's card.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "sequence_competences"
    repo TeacherAssistant.Repo

    references do
      reference :teaching_context,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        on_delete: :delete,
        index?: true

      reference :sequence,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        on_delete: :delete,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :upsert do
      accept [:teaching_context_id, :sequence_id, :text]
      upsert? true
      upsert_identity :unique_per_sequence
      upsert_fields [:text]
    end

    destroy :destroy do
      primary? true
      require_atomic? false
    end

    read :for_contexts do
      argument :context_ids, {:array, :uuid}, allow_nil?: false
      argument :sequence_ids, {:array, :uuid}, allow_nil?: false

      filter expr(
               teaching_context_id in ^arg(:context_ids) and sequence_id in ^arg(:sequence_ids)
             )
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :destroy]) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      forbid_unless Checks.SchoolVerified
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if expr(teaching_context.teacher_user_id == ^actor(:id))
      # A combined course's teacher writes it for every member class, even one since
      # reassigned to a colleague (the competence is written once for the course).
      authorize_if expr(teaching_context.combined_course.teacher_user_id == ^actor(:id))
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: [:sequence, :term]},
      on: [:create, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :text, :string, allow_nil?: false, public?: true, constraints: [max_length: 140]
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_per_sequence, [:teaching_context_id, :sequence_id]
  end
end
