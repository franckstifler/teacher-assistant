defmodule TeacherAssistant.Accounts.PhoneAccountsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Accounts.User.Preparations.ThrottleSignIn

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

    test "ten failures in a row lock the number for a while, even with the right password" do
      seed_phone_user("+237677555001", "secret-pass-1")

      for _ <- 1..10 do
        assert {:error, %AshAuthentication.Errors.AuthenticationFailed{} = error} =
                 sign_in_by_phone("677555001", "wrong-pass")

        refute ThrottleSignIn.throttled?(error)
      end

      assert {:error, error} = sign_in_by_phone("677555001", "secret-pass-1")
      assert ThrottleSignIn.throttled?(error)

      # Another account is not affected.
      seed_phone_user("+237677555002", "secret-pass-2")
      assert {:ok, _} = sign_in_by_phone("677555002", "secret-pass-2")
    end

    test "a successful sign-in clears the failures" do
      seed_phone_user("+237677555003", "secret-pass-1")

      for _ <- 1..9, do: {:error, _} = sign_in_by_phone("677555003", "wrong-pass")
      assert {:ok, _} = sign_in_by_phone("677555003", "secret-pass-1")

      for _ <- 1..9, do: {:error, _} = sign_in_by_phone("677555003", "wrong-pass")
      assert {:ok, _} = sign_in_by_phone("677555003", "secret-pass-1")
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

    test "a head of two schools only manages accounts of the school they act in" do
      %{scope: scope_a, head_user: head_a} = TeacherFixtures.setup_complete_school_fixture()
      scope_b = head_scope()
      TeacherFixtures.membership_fixture(scope_b, %{user: head_a, roles: [:head]})
      head_a_in_b = TeacherAssistant.DataCase.school_scope(head_a, scope_b.current_workspace)

      {:ok, user_a} = create_by_school(scope_a, %{phone: "677123456"})
      # As `Accounts.create_member` does: the new account is a member of A.
      TeacherFixtures.membership_fixture(scope_a, %{user: user_a, roles: [:teacher]})

      # Cannot create an account for A while acting in B...
      assert {:error, %Ash.Error.Forbidden{}} =
               create_by_school(head_a_in_b, %{
                 phone: "677000111",
                 created_in_workspace_id: scope_a.current_workspace.id
               })

      # ...nor reset A's account while acting in B...
      assert {:error, %Ash.Error.Forbidden{}} =
               user_a
               |> Ash.Changeset.for_update(:reset_temporary_password, %{}, scope: head_a_in_b)
               |> Ash.update()

      # ...but can while acting in A.
      assert {:ok, reset} =
               user_a
               |> Ash.Changeset.for_update(:reset_temporary_password, %{}, scope: scope_a)
               |> Ash.update()

      assert {:ok, _} = sign_in_by_phone("677123456", reset.__metadata__.temporary_password)
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

  describe "set_own_password without a pending temporary password" do
    test "is refused, even to the user themself" do
      scope = head_scope()
      head = scope.current_user
      refute head.must_change_password

      assert {:error, %Ash.Error.Forbidden{}} =
               head
               |> Ash.Changeset.for_update(
                 :set_own_password,
                 %{password: "new-pass-123", password_confirmation: "new-pass-123"},
                 actor: head
               )
               |> Ash.update()
    end
  end

  alias TeacherAssistant.Accounts

  defp member_ids(scope), do: scope |> Accounts.list_members() |> Enum.map(& &1.user_id)

  defp membership_of(scope, user),
    do: Enum.find(Accounts.list_members(scope), &(&1.user_id == user.id))

  describe "add_member_by_phone" do
    test "new number: creates the account and the membership" do
      scope = head_scope()

      assert {:ok, %{user: user, temporary_password: pw}} =
               Accounts.add_member_by_phone(scope, %{
                 name: "Awa Nji",
                 phone: "677 12 34 56",
                 roles: [:teacher]
               })

      assert is_binary(pw)
      assert user.id in member_ids(scope)
    end

    test "existing account: linked, its name and password untouched" do
      scope_a = head_scope()
      scope_b = head_scope()

      {:ok, %{user: user, temporary_password: pw}} =
        Accounts.add_member_by_phone(scope_a, %{
          name: "Awa Nji",
          phone: "677123456",
          roles: [:teacher]
        })

      assert {:ok, %{user: linked, temporary_password: nil}} =
               Accounts.add_member_by_phone(scope_b, %{
                 name: "Autre Nom",
                 phone: "+237 677 12 34 56",
                 roles: [:teacher]
               })

      assert linked.id == user.id
      assert linked.id in member_ids(scope_b)
      reloaded = Ash.get!(User, user.id, authorize?: false)
      assert reloaded.name == "Awa Nji"
      assert {:ok, _} = sign_in_by_phone("677123456", pw)
    end

    test "already an active member" do
      scope = head_scope()
      attrs = %{name: "Awa Nji", phone: "677123456", roles: [:teacher]}
      {:ok, _} = Accounts.add_member_by_phone(scope, attrs)
      assert {:error, :already_member} = Accounts.add_member_by_phone(scope, attrs)
    end

    test "invalid phone" do
      assert {:error, :invalid_phone} =
               Accounts.add_member_by_phone(head_scope(), %{
                 name: "X",
                 phone: "12",
                 roles: [:teacher]
               })
    end

    test "a non-head cannot add members" do
      scope = head_scope()
      teacher_scope = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

      assert {:error, :forbidden} =
               Accounts.add_member_by_phone(teacher_scope, %{
                 name: "X",
                 phone: "677123456",
                 roles: [:teacher]
               })
    end
  end

  describe "reset_member_password" do
    test "the creating school resets: new password, old one stops working, sessions revoked" do
      scope = head_scope()

      {:ok, %{user: user, temporary_password: old}} =
        Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      {:ok, signed_in} = sign_in_by_phone("677123456", old)
      token = signed_in.__metadata__.token

      assert {:ok, new} = Accounts.reset_member_password(scope, membership_of(scope, user))
      assert new != old
      assert {:error, _} = sign_in_by_phone("677123456", old)
      assert {:ok, _} = sign_in_by_phone("677123456", new)

      assert AshAuthentication.TokenResource.token_revoked?(
               TeacherAssistant.Accounts.Token,
               token
             )
    end

    test "linked account cannot be reset" do
      scope_a = head_scope()
      scope_b = head_scope()

      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(scope_a, %{
          name: "Awa",
          phone: "677123456",
          roles: [:teacher]
        })

      {:ok, _} =
        Accounts.add_member_by_phone(scope_b, %{
          name: "Awa",
          phone: "677123456",
          roles: [:teacher]
        })

      refute Accounts.can_reset_member_password?(scope_b, user)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.reset_member_password(scope_b, membership_of(scope_b, user))
    end

    test "the creating school cannot reset while the person is active in another school" do
      scope_a = head_scope()
      scope_b = head_scope()

      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(scope_a, %{
          name: "Awa",
          phone: "677123456",
          roles: [:teacher]
        })

      assert Accounts.can_reset_member_password?(scope_a, user)

      {:ok, _} =
        Accounts.add_member_by_phone(scope_b, %{
          name: "Awa",
          phone: "677123456",
          roles: [:teacher]
        })

      refute Accounts.can_reset_member_password?(scope_a, user)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.reset_member_password(scope_a, membership_of(scope_a, user))

      {:ok, _} = Accounts.deactivate_member(scope_b, membership_of(scope_b, user))

      assert Accounts.can_reset_member_password?(scope_a, user)

      assert {:ok, _password} =
               Accounts.reset_member_password(scope_a, membership_of(scope_a, user))
    end

    test "the clear temporary password never shows when the changeset is inspected" do
      scope = head_scope()

      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      {changeset, _} =
        user
        |> Ash.Changeset.for_update(:reset_temporary_password, %{}, authorize?: false)
        |> Ash.Changeset.run_before_actions()

      password = changeset.context.private.temporary_password
      assert password =~ ~r/[a-z]{4}-[a-z]{4}-\d{4}/
      refute inspect(changeset) =~ password
    end

    test "an operator's account is never reset" do
      scope = head_scope()

      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(scope, %{name: "Op", phone: "677123456", roles: [:teacher]})

      {:ok, _} = Accounts.promote_to_admin(user, authorize?: false)

      refute Accounts.can_reset_member_password?(
               scope,
               Ash.get!(User, user.id, authorize?: false)
             )
    end
  end

  test "temporary_password_expired?/1" do
    past = DateTime.add(DateTime.utc_now(), -1, :day)
    future = DateTime.add(DateTime.utc_now(), 1, :day)

    assert Accounts.temporary_password_expired?(%User{
             must_change_password: true,
             temporary_password_expires_at: past
           })

    refute Accounts.temporary_password_expired?(%User{
             must_change_password: true,
             temporary_password_expires_at: future
           })

    refute Accounts.temporary_password_expired?(%User{
             must_change_password: false,
             temporary_password_expires_at: past
           })
  end
end
