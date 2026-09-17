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
  alias TeacherAssistant.{Accounts, Academics}
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

  ws = Academics.ensure_personal_workspace!(user)

  # Create or fetch academic year
  year =
    case Academics.create_academic_year(ws, %{
           name: "2025-2026",
           start_date: ~D[2025-09-08],
           end_date: ~D[2026-07-31],
           active: true
         }) do
      {:ok, y} -> y
      _ -> ws |> Academics.list_academic_years() |> Enum.find(&(&1.name == "2025-2026"))
    end

  # Build default calendar only if year has no sequences
  if year && Academics.list_sequences(year) == [] do
    Academics.build_default_calendar(year)
  end

  # Create or fetch teaching context
  ctx =
    if year do
      existing =
        ws
        |> Academics.list_teaching_contexts(year)
        |> Enum.find(&(&1.subject == "Mathématiques" && &1.level == "6ème"))

      existing ||
        case Academics.create_teaching_context(ws, year, %{
               subject: "Mathématiques",
               level: "6ème",
               subsystem: :francophone,
               weekly_hours: 4
             }) do
          {:ok, c} -> c
          _ -> nil
        end
    end

  # Create progression plan only if none exist
  if ctx && Academics.list_progression_plans(ws) == [] do
    Academics.create_progression_plan(ctx, %{title: "Mathématiques 6ème 2025-2026"})
  end
end
