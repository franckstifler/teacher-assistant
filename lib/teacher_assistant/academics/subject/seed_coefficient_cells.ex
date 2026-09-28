defmodule TeacherAssistant.Academics.Subject.SeedCoefficientCells do
  @moduledoc """
  A new subject is taught everywhere by default: one blank-série cell per level of
  the school's subsystem(s), at the subject's `default_coefficient`. The admin then
  empties the cells where it is not taught. Runs inside the subject's create
  (covers both `Curriculum.create_subject/2` and the catalog seeded at school
  creation, after the profile exists).
  """
  use Ash.Resource.Change
  require Ash.Query

  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.{SchoolTemplates, SubjectCoefficient}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, subject ->
      case school_profile(subject.workspace_id) do
        nil -> {:ok, subject}
        profile -> seed(subject, profile)
      end
    end)
  end

  # Internal read of the owning school's profile (the subject create is already
  # authorized; this is its own side effect).
  defp school_profile(workspace_id) do
    SchoolProfile
    |> Ash.Query.filter(workspace_id == ^workspace_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp seed(subject, profile) do
    inputs =
      for subsystem <- SchoolTemplates.grid_subsystems(profile.subsystem),
          level <- SchoolTemplates.levels_for(profile.school_type, subsystem) do
        %{
          subject_id: subject.id,
          subsystem: subsystem,
          level: level,
          serie: nil,
          coefficient: subject.default_coefficient
        }
      end

    case Ash.bulk_create(inputs, SubjectCoefficient, :create,
           tenant: subject.workspace_id,
           authorize?: false,
           return_errors?: true,
           stop_on_error?: true
         ) do
      %Ash.BulkResult{status: :success} -> {:ok, subject}
      %Ash.BulkResult{errors: [error | _]} -> {:error, error}
    end
  end
end
