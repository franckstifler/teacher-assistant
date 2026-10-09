defmodule TeacherAssistant.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's own table: not an Ash resource, so `mix ash.codegen` cannot generate it.
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
