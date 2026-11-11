defmodule TeacherAssistant.Accounts.AccountDeletionTest do
  @moduledoc "A member of no school deletes their own account (A9)."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Scope, TeacherFixtures}
  alias TeacherAssistant.Accounts.User

  defp reload(user), do: Ash.get!(User, user.id, authorize?: false)

  defp sign_in(email, password) do
    User
    |> AshAuthentication.Info.strategy!(:password)
    |> AshAuthentication.Strategy.action(:sign_in, %{"email" => email, "password" => password})
  end

  test "a user with no active membership deletes their account: identity cleared" do
    user = TeacherFixtures.user_fixture(%{name: "Paul Ancien"})
    assert {:ok, _} = sign_in(to_string(user.email), "password1234")

    assert :ok = Accounts.delete_own_account(%Scope{current_user: user})
    deleted = reload(user)
    assert {deleted.email, deleted.phone, deleted.name} == {nil, nil, "Compte supprimé"}
    assert {:error, _} = sign_in(to_string(user.email), "password1234")
  end

  test "a member of a school is refused; a deactivated membership no longer blocks" do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    m = TeacherFixtures.membership_fixture(head, %{roles: [:teacher]})
    member = reload(%{id: m.user_id})

    assert {:error, :has_membership} = Accounts.delete_own_account(%Scope{current_user: member})
    assert reload(member).email == member.email

    {:ok, _} = Accounts.deactivate_member(head, m)
    assert :ok = Accounts.delete_own_account(%Scope{current_user: member})
  end

  test "nobody deletes someone else's account" do
    user = TeacherFixtures.user_fixture()
    other = TeacherFixtures.user_fixture()

    assert {:error, %Ash.Error.Forbidden{}} =
             user
             |> Ash.Changeset.for_update(:delete_own_account, %{}, actor: other)
             |> Ash.update()
  end
end
