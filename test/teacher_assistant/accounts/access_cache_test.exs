defmodule TeacherAssistant.Accounts.AccessCacheTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.AccessCache
  alias TeacherAssistant.Accounts.Checks.{SchoolRole, SchoolVerified}
  alias TeacherAssistant.TeacherFixtures

  describe "the cache" do
    test "reads once, then answers from memory until forgotten" do
      {user, ws} = {Ecto.UUID.generate(), Ecto.UUID.generate()}
      counter = :counters.new(1, [])
      read = fn -> :counters.add(counter, 1, 1) && [:teacher] end

      assert AccessCache.roles(user, ws, read) == [:teacher]
      assert AccessCache.roles(user, ws, read) == [:teacher]
      assert :counters.get(counter, 1) == 1

      AccessCache.forget_member(user, ws)
      assert AccessCache.roles(user, ws, read) == [:teacher]
      assert :counters.get(counter, 1) == 2
    end

    test "an answer older than 5 seconds is read again" do
      {user, ws} = {Ecto.UUID.generate(), Ecto.UUID.generate()}
      old = System.monotonic_time(:millisecond) - 6_000
      :ets.insert(AccessCache, {{:roles, user, ws}, [:head], old})

      assert AccessCache.roles(user, ws, fn -> nil end) == nil
    end
  end

  describe "a change is seen at once" do
    test "a deactivated member is refused on the next check" do
      %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
      ws_id = head.current_workspace.id
      m = TeacherFixtures.membership_fixture(head, %{roles: [:teacher]})
      user = %{id: m.user_id}

      assert SchoolRole.holds?(user, ws_id, :member)
      {:ok, _} = Accounts.deactivate_member(head, m)
      refute SchoolRole.holds?(user, ws_id, :member)
    end

    test "a role change is seen on the next check" do
      %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
      ws_id = head.current_workspace.id
      m = TeacherFixtures.membership_fixture(head, %{roles: [:teacher]})
      user = %{id: m.user_id}

      refute SchoolRole.holds?(user, ws_id, :admin)
      {:ok, _} = Accounts.update_member_roles(head, m, [:vice_principal])
      assert SchoolRole.holds?(user, ws_id, :admin)
    end

    test "verifying a school is seen on the next check" do
      %{scope: head} = TeacherFixtures.setup_complete_school_fixture(%{verified: false})
      ws_id = head.current_workspace.id

      refute SchoolVerified.verified?(ws_id)
      :ok = TeacherFixtures.verify_school!(head)
      assert SchoolVerified.verified?(ws_id)
    end
  end
end
