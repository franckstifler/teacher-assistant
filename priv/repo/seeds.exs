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
  alias TeacherAssistant.{Accounts, Academics}
  email = "demo@example.com"

  user =
    case Accounts.create_user(%{
           email: email,
           password: "password1234",
           password_confirmation: "password1234"
         }) do
      {:ok, u} -> u
      _ -> Ash.read_first!(Ash.Query.filter(Accounts.User, email == ^email), authorize?: false)
    end

  ws = Academics.ensure_personal_workspace!(user)

  {:ok, year} =
    Academics.create_academic_year(ws, %{
      name: "2025-2026",
      start_date: ~D[2025-09-08],
      end_date: ~D[2026-07-31],
      active: true
    })

  :ok = Academics.build_default_calendar(year)

  {:ok, ctx} =
    Academics.create_teaching_context(ws, year, %{
      subject: "Mathématiques",
      level: "6ème",
      subsystem: :francophone,
      weekly_hours: 4
    })

  {:ok, _plan} = Academics.create_progression_plan(ctx, %{title: "Mathématiques 6ème 2025-2026"})
end
