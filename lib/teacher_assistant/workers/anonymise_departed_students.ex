defmodule TeacherAssistant.Workers.AnonymiseDepartedStudents do
  @moduledoc """
  Weekly (spec audit follow-ups A9): in every school, suspended ones included, the
  students who left three years ago or more are anonymised
  (`Enrollment.anonymise_due_students/2`). One school's failure is logged and the
  others still run.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Enrollment

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    total =
      Workspace
      |> Ash.read!(authorize?: false)
      |> Enum.reduce(0, fn ws, acc ->
        try do
          acc + Enrollment.anonymise_due_students(ws.id).anonymised
        rescue
          error ->
            Logger.warning(
              "anonymisation failed for workspace #{ws.id}: #{Exception.message(error)}"
            )

            acc
        end
      end)

    Logger.info("anonymised #{total} departed student(s)")
    :ok
  end
end
