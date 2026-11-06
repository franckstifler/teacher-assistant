defmodule TeacherAssistant.Repo.Migrations.AddErrorTracker do
  @moduledoc """
  ErrorTracker's own tables (error_tracker_errors, _occurrences, _meta). Not Ash
  resources, so `mix ash.codegen` cannot write this one: it calls the library's
  versioned migration. A later ErrorTracker release that needs version 6 gets a
  new migration calling `up(version: 6)`.
  """
  use Ecto.Migration

  def up, do: ErrorTracker.Migration.up(version: 5)

  def down, do: ErrorTracker.Migration.down()
end
