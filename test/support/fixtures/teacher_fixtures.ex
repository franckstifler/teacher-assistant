defmodule TeacherAssistant.TeacherFixtures do
  @moduledoc """
  Test helpers for the teacher-first MVP.
  """

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics

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

  def workspace_fixture(user \\ user_fixture()) do
    Accounts.ensure_personal_workspace!(user)
  end

  def academic_year_fixture(user \\ user_fixture(), attrs \\ %{}) do
    workspace = Accounts.ensure_personal_workspace!(user)

    {:ok, academic_year} =
      Academics.create_academic_year(workspace, %{
        name: Map.get(attrs, :name, "2026-2027"),
        start_date: Map.get(attrs, :start_date, ~D[2026-09-01]),
        end_date: Map.get(attrs, :end_date, ~D[2027-06-30]),
        active: Map.get(attrs, :active, true)
      })

    {user, workspace, academic_year}
  end

  def classroom_fixture(user \\ user_fixture(), attrs \\ %{}) do
    {user, workspace, academic_year} = academic_year_fixture(user)

    {:ok, classroom} =
      Academics.create_personal_classroom(workspace, academic_year, %{
        class_label: Map.get(attrs, :class_label, "Form 3"),
        subject: Map.get(attrs, :subject, "Mathematics")
      })

    {user, workspace, academic_year, classroom}
  end

  def learner_fixture(classroom, attrs \\ %{}) do
    {:ok, learner} =
      Academics.create_learner(classroom, %{
        first_name: Map.get(attrs, :first_name, "Grace"),
        last_name: Map.get(attrs, :last_name, "Nkom"),
        identifier: Map.get(attrs, :identifier, "L-#{System.unique_integer([:positive])}")
      })

    learner
  end
end
