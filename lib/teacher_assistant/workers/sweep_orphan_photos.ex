defmodule TeacherAssistant.Workers.SweepOrphanPhotos do
  @moduledoc """
  Weekly (spec audit follow-ups A9): deletes the upload files nothing points at
  (`Uploads.sweep_orphans/2`) and journals the counts, which the operators' morning
  digest reports. `args["root"]` overrides the uploads directory (tests).
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias TeacherAssistant.Accounts.AuditEvent
  alias TeacherAssistant.Uploads

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    counts = Uploads.sweep_orphans(Map.get(args, "root") || Uploads.dir())

    AuditEvent
    |> Ash.Changeset.for_create(:record, %{
      action: :files_swept,
      details: %{"deleted" => counts.deleted, "kept" => counts.kept}
    })
    |> Ash.create!(authorize?: false)

    Logger.info("orphan upload sweep: #{counts.deleted} deleted, #{counts.kept} kept")
    :ok
  end
end
