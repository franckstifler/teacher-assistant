defmodule TeacherAssistant.Accounts.StatutoryHoursTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    m = TeacherFixtures.membership_fixture(scope)
    %{scope: scope, m: m}
  end

  test "the school service defaults to 18 and accepts 1..40", %{scope: scope} do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.statutory_hours == 18
    assert {:ok, %{statutory_hours: 21}} = Accounts.update_school_service(scope, "21")
    assert {:error, :invalid_hours} = Accounts.update_school_service(scope, "0")
    assert {:error, :invalid_hours} = Accounts.update_school_service(scope, "x")
  end

  test "a member's own service overrides, empty clears", %{scope: scope, m: m} do
    assert m.statutory_hours == nil
    assert {:ok, %{statutory_hours: 12}} = Accounts.set_member_service(scope, m, "12")
    {:ok, m} = Accounts.set_member_service(scope, m, "12")
    assert {:ok, %{statutory_hours: nil}} = Accounts.set_member_service(scope, m, "")
    assert {:error, :invalid_hours} = Accounts.set_member_service(scope, m, "41")
  end

  test "a Censeur may set a member's service; a plain teacher may not", %{scope: scope, m: m} do
    censeur = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal]})
    assert Accounts.can_set_member_service?(censeur)
    assert {:ok, _} = Accounts.set_member_service(censeur, m, "15")

    teacher = TeacherFixtures.member_scope_fixture(scope)
    refute Accounts.can_set_member_service?(teacher)
    assert {:error, %Ash.Error.Forbidden{}} = Accounts.set_member_service(teacher, m, "15")
  end
end
