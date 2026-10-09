defmodule TeacherAssistant.Workers.ExpiredTemporaryPasswordsTest do
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  import Ecto.Query

  alias TeacherAssistant.{Notifications, TeacherFixtures}
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Workers.ExpiredTemporaryPasswords

  setup do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    censeur = TeacherFixtures.member_scope_fixture(head, %{roles: [:vice_principal]})
    teacher = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]})
    a = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]}).current_user
    b = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]}).current_user
    c = TeacherFixtures.member_scope_fixture(head, %{roles: [:teacher]}).current_user

    now = DateTime.utc_now()
    set(a, true, DateTime.add(now, -2, :hour))
    set(b, false, DateTime.add(now, -2, :hour))
    set(c, true, DateTime.add(now, -3, :day))

    %{head: head, censeur: censeur, teacher: teacher, a: a, b: b, c: c}
  end

  defp set(user, must_change, expires_at) do
    TeacherAssistant.Repo.update_all(
      from(u in "users", where: u.id == type(^user.id, :binary_id)),
      set: [must_change_password: must_change, temporary_password_expires_at: expires_at]
    )
  end

  test "reports an account expired in the last 24 hours once, never a used one", ctx do
    assert :ok = perform_job(ExpiredTemporaryPasswords, %{})

    for admin <- [ctx.head, ctx.censeur] do
      assert [%{kind: :temporary_password_expired, params: %{"name" => name, "expired_on" => on}}] =
               Notifications.inbox(admin, 1).results

      assert name == User.display_name(ctx.a)
      assert on =~ ~r|^\d{2}/\d{2}/\d{4}$|
    end

    assert Notifications.inbox(ctx.teacher, 1).results == []
  end

  test "a later run does not report it again once outside the window", ctx do
    assert :ok = perform_job(ExpiredTemporaryPasswords, %{})
    set(ctx.a, true, DateTime.add(DateTime.utc_now(), -26, :hour))
    assert :ok = perform_job(ExpiredTemporaryPasswords, %{})
    assert length(Notifications.inbox(ctx.head, 1).results) == 1
  end
end
