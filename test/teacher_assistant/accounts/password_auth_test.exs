defmodule TeacherAssistant.Accounts.PasswordAuthTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Accounts.UserSchool
  alias TeacherAssistant.Academics.School
  require Ash.Query

  test "seeded development users can sign in with password and have a school membership" do
    TeacherAssistant.Seed.seed()

    strategy = AshAuthentication.Info.strategy!(User, :password)

    assert {:ok, user} =
             AshAuthentication.Strategy.action(strategy, :sign_in, %{
               email: "admin@admin.com",
               password: "password1234"
             })

    assert user.role == :admin

    school =
      School
      |> Ash.Query.filter(name == "Lycee Technique de Douala")
      |> Ash.read_one!(authorize?: false)

    assert %UserSchool{} =
             UserSchool
             |> Ash.Query.filter(user_id == ^user.id)
             |> Ash.read_one!(tenant: school.id, authorize?: false)
  end
end
