defmodule TeacherAssistant.Repo do
  use AshPostgres.Repo,
    otp_app: :teacher_assistant

  @impl true
  def installed_extensions, do: ["ash-functions", "citext"]

  @impl true
  def prefer_transaction?, do: false

  @impl true
  def min_pg_version, do: %Version{major: 14, minor: 18, patch: 0}
end
