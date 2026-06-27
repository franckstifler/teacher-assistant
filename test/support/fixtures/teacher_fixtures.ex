defmodule TeacherAssistant.TeacherFixtures do
  alias TeacherAssistant.{Accounts, Academics}

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, "teacher-#{System.unique_integer([:positive])}@example.com")

    {:ok, user} =
      Accounts.create_user(%{
        email: email,
        password: Map.get(attrs, :password, "password1234"),
        password_confirmation: Map.get(attrs, :password_confirmation, "password1234")
      })

    user
  end

  def workspace_fixture(user \\ user_fixture()), do: Academics.ensure_personal_workspace!(user)
end
