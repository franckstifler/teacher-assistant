defmodule TeacherAssistant.Academics.Mark do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "marks"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:score, :assessment_id, :student_id],
      update: [:score]
    ]

    read :for_assessment do
      argument :assessment_id, :uuid, allow_nil?: false
      filter expr(assessment_id == ^arg(:assessment_id))
    end

    read :for_assessments do
      argument :assessment_ids, {:array, :uuid}, allow_nil?: false
      filter expr(assessment_id in ^arg(:assessment_ids))
    end

    # Upserts marks across one or more assessments in a single transaction
    # (`transaction? true`), so the save is all-or-nothing: if any write fails
    # the whole batch rolls back — one class's failure can never leave another
    # class's mark persisted.
    #
    # Each `%{assessment_id, student_id, score}` entry carries its own
    # `assessment_id`, so a student's score is routed to *their own* class's
    # assessment (the combined-marks per-class-routing invariant). The
    # `[:assessment_id, :student_id]` identity means an existing mark is
    # updated in place (score only) rather than duplicated. A `nil` score is
    # valid — it records the student absent.
    #
    # Resource notifications are collected via `return_notifications?: true`
    # and returned as the third element of `{:ok, result, notifications}`, so
    # Ash dispatches them only *after* the transaction commits — the deferred
    # broadcast that keeps rolled-back rows from producing phantom PubSub
    # events. (Task E1 replaces this manual collection with an
    # `Ash.Notifier.PubSub` notifier.)
    action :upsert_all, :atom do
      argument :marks, {:array, :map}, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        input.arguments.marks
        |> Enum.group_by(& &1.assessment_id)
        |> Enum.reduce_while({:ok, []}, fn {assessment_id, entries}, {:ok, acc} ->
          case upsert_group(assessment_id, entries) do
            {:ok, notifications} -> {:cont, {:ok, acc ++ notifications}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, notifications} -> {:ok, :ok, notifications}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :score, :decimal, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :assessment, TeacherAssistant.Academics.Assessment do
      source_attribute :assessment_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_mark, [:assessment_id, :student_id]
  end

  # Upserts one assessment's marks by the `[:assessment_id, :student_id]`
  # identity: an existing mark is updated (score only), a new one created.
  # Returns the collected resource notifications, or `{:error, reason}` to roll
  # back the whole transaction. Deliberately without its own transaction — the
  # `:upsert_all` action wraps every group in one shared transaction, so a
  # failure here rolls back every group's writes, not just this one's.
  defp upsert_group(assessment_id, entries) do
    existing =
      __MODULE__
      |> Ash.Query.for_read(:for_assessment, %{assessment_id: assessment_id})
      |> Ash.read!()
      |> Map.new(fn mark -> {mark.student_id, mark} end)

    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      result =
        case Map.get(existing, entry.student_id) do
          nil ->
            __MODULE__
            |> Ash.Changeset.for_create(:create, %{
              assessment_id: assessment_id,
              student_id: entry.student_id,
              score: Map.get(entry, :score)
            })
            |> Ash.create(return_notifications?: true)

          %__MODULE__{} = mark ->
            mark
            |> Ash.Changeset.for_update(:update, %{score: Map.get(entry, :score)})
            |> Ash.update(return_notifications?: true)
        end

      case result do
        {:ok, _mark, notifications} -> {:cont, {:ok, acc ++ notifications}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
