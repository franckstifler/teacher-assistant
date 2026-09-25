# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     TeacherAssistant.Repo.insert!(%TeacherAssistant.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

if Mix.env() == :dev do
  require Ash.Query
  alias TeacherAssistant.{Accounts, Organization}
  alias TeacherAssistant.Academics.Seeding

  email = "demo@example.com"

  user =
    case Accounts.create_user(%{
           email: email,
           password: "password1234",
           password_confirmation: "password1234"
         }) do
      {:ok, u} ->
        u

      _ ->
        Accounts.User
        |> Ash.Query.filter(email == ^email)
        |> Ash.read_first!(authorize?: false)
    end

  # Promote the demo user to :admin (dev only) so /admin/schools is reachable locally.
  user =
    if user.role == :admin do
      user
    else
      {:ok, admin} = Accounts.promote_to_admin(user)
      admin
    end

  # Create or fetch the demo school workspace (head membership is created for
  # us by `create_school`, along with its profile and seeded subject catalog).
  head_scope = %TeacherAssistant.Scope{current_user: user}

  ws =
    case Organization.list_workspaces_for(head_scope) do
      [existing | _] ->
        existing

      [] ->
        {:ok, workspace} =
          Organization.create_school(head_scope, %{name: "Lycée de démonstration"})

        workspace
    end

  {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(user, ws.id)

  # Create or fetch the active academic year.
  year =
    case Organization.current_academic_year(scope) do
      nil ->
        {:ok, y} =
          Organization.create_academic_year(scope, %{
            name: "2025-2026",
            start_date: ~D[2025-09-08],
            end_date: ~D[2026-07-31],
            active: true
          })

        y

      existing ->
        existing
    end

  # Seed the year's default calendar (idempotent, no-op once séquences exist).
  Organization.build_default_calendar(scope, year)

  # Seed the starter class groups for the school's type/subsystem (idempotent,
  # no-op once the school already has class groups).
  Seeding.seed_starter_classes(scope, year)
end
