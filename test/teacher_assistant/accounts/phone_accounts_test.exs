defmodule TeacherAssistant.Accounts.PhoneAccountsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Accounts.User

  defp seed_phone_user(phone, password, attrs \\ %{}) do
    {:ok, hash} = AshAuthentication.BcryptProvider.hash(password)

    Ash.Seed.seed!(
      User,
      Map.merge(%{phone: phone, name: "Prof Téléphone", hashed_password: hash}, attrs)
    )
  end

  defp sign_in_by_phone(phone, password) do
    strategy = AshAuthentication.Info.strategy!(User, :phone)

    AshAuthentication.Strategy.action(strategy, :sign_in, %{
      "phone" => phone,
      "password" => password
    })
  end

  describe "sign in by phone" do
    test "sign in by phone in any format" do
      user = seed_phone_user("+237677123456", "secret-pass-1")

      for typed <- ["677123456", "6 77 12 34 56", "+237 677 12 34 56", "00237677123456"] do
        assert {:ok, signed_in} = sign_in_by_phone(typed, "secret-pass-1"), "failed for #{typed}"
        assert signed_in.id == user.id
      end
    end

    test "a wrong password or unknown number fails the same way" do
      seed_phone_user("+237677123456", "secret-pass-1")

      assert {:error, %AshAuthentication.Errors.AuthenticationFailed{}} =
               sign_in_by_phone("677123456", "wrong-pass")

      assert {:error, %AshAuthentication.Errors.AuthenticationFailed{}} =
               sign_in_by_phone("699999999", "secret-pass-1")
    end

    test "the email strategy is unchanged" do
      user = TeacherAssistant.TeacherFixtures.user_fixture(%{email: "mail@example.com"})
      strategy = AshAuthentication.Info.strategy!(User, :password)

      assert {:ok, signed_in} =
               AshAuthentication.Strategy.action(strategy, :sign_in, %{
                 "email" => "mail@example.com",
                 "password" => "password1234"
               })

      assert signed_in.id == user.id
    end
  end

  describe "identity and display" do
    test "the phone is unique" do
      seed_phone_user("+237677123456", "secret-pass-1")

      assert_raise Ash.Error.Invalid, fn ->
        User
        |> Ash.Changeset.for_create(:create, %{phone: "677123456"})
        |> Ash.create!(authorize?: false)
      end
    end

    test "an account needs an email or a phone" do
      assert {:error, %Ash.Error.Invalid{}} =
               User
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create(authorize?: false)
    end

    test "display_name and contact fall back to email, then phone" do
      assert User.display_name(%User{name: "Awa", email: nil, phone: nil}) == "Awa"
      assert User.display_name(%User{name: nil, email: "a@b.cm", phone: nil}) == "a@b.cm"

      assert User.display_name(%User{name: nil, email: nil, phone: "+237677123456"}) ==
               "6 77 12 34 56"

      assert User.contact(%User{email: "a@b.cm", phone: "+237677123456"}) == "a@b.cm"
      assert User.contact(%User{email: nil, phone: "+237677123456"}) == "6 77 12 34 56"
      assert User.contact(%User{email: nil, phone: nil}) == nil
    end
  end

  alias TeacherAssistant.TeacherFixtures

  defp head_scope do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()
    scope
  end

  defp create_by_school(scope, attrs) do
    User
    |> Ash.Changeset.for_create(
      :create_by_school,
      Map.merge(%{name: "Awa Nji", created_in_workspace_id: scope.current_workspace.id}, attrs),
      scope: scope
    )
    |> Ash.create()
  end

  describe "create_by_school" do
    test "a head creates a phone account with a temporary password" do
      scope = head_scope()
      assert {:ok, user} = create_by_school(scope, %{phone: "6 77 12 34 56"})

      assert user.phone == "+237677123456"
      assert user.must_change_password
      assert user.created_in_workspace_id == scope.current_workspace.id
      assert DateTime.diff(user.temporary_password_expires_at, DateTime.utc_now(), :day) in 6..7

      password = user.__metadata__.temporary_password
      assert password =~ ~r/\A[a-z]{4}-[a-z]{4}-\d{4}\z/
      assert {:ok, _} = sign_in_by_phone("677123456", password)
    end

    test "a non-head member cannot create accounts" do
      scope = head_scope()
      teacher_scope = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

      assert {:error, %Ash.Error.Forbidden{}} =
               create_by_school(teacher_scope, %{
                 phone: "677123456",
                 created_in_workspace_id: scope.current_workspace.id
               })
    end

    test "a head cannot create an account on behalf of another school" do
      scope = head_scope()
      other = head_scope()

      assert {:error, %Ash.Error.Forbidden{}} =
               create_by_school(scope, %{
                 phone: "677123456",
                 created_in_workspace_id: other.current_workspace.id
               })
    end

    test "a duplicate phone is reported as an identity error" do
      scope = head_scope()
      {:ok, _} = create_by_school(scope, %{phone: "677123456"})
      assert {:error, error} = create_by_school(scope, %{phone: "+237677123456"})
      assert TeacherAssistant.Accounts.phone_taken?(error)
    end
  end

  describe "set_own_password" do
    test "the user replaces the temporary password and the flags clear" do
      scope = head_scope()
      {:ok, user} = create_by_school(scope, %{phone: "677123456"})

      assert {:ok, updated} =
               user
               |> Ash.Changeset.for_update(
                 :set_own_password,
                 %{password: "my-own-pass", password_confirmation: "my-own-pass"},
                 actor: user
               )
               |> Ash.update()

      refute updated.must_change_password
      assert updated.temporary_password_expires_at == nil
      assert {:ok, _} = sign_in_by_phone("677123456", "my-own-pass")
    end

    test "confirmation must match and length is at least 8" do
      scope = head_scope()
      {:ok, user} = create_by_school(scope, %{phone: "677123456"})

      for {pw, confirm} <- [{"my-own-pass", "other-pass"}, {"short", "short"}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 user
                 |> Ash.Changeset.for_update(
                   :set_own_password,
                   %{password: pw, password_confirmation: confirm},
                   actor: user
                 )
                 |> Ash.update()
      end
    end

    test "nobody else can set it" do
      scope = head_scope()
      {:ok, user} = create_by_school(scope, %{phone: "677123456"})

      assert {:error, %Ash.Error.Forbidden{}} =
               user
               |> Ash.Changeset.for_update(
                 :set_own_password,
                 %{password: "my-own-pass", password_confirmation: "my-own-pass"},
                 actor: scope.current_user
               )
               |> Ash.update()
    end
  end
end
