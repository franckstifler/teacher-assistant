defmodule TeacherAssistant.Repo.Migrations.EnsureObanSuspendedState do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TYPE "public".oban_job_state ADD VALUE IF NOT EXISTS 'suspended' BEFORE 'scheduled'
    """)
  end

  def down do
    :ok
  end
end
