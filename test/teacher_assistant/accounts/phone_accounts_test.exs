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
end
