defmodule Mix.Tasks.TeacherAssistant.MakeOperatorTest do
  use TeacherAssistant.DataCase, async: false

  import ExUnit.CaptureIO
  alias TeacherAssistant.TeacherFixtures

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "promotes a user found by email" do
    user = TeacherFixtures.user_fixture()
    Mix.Tasks.TeacherAssistant.MakeOperator.run([to_string(user.email)])

    assert_received {:mix_shell, :info, [message]}
    assert message =~ "opérateur"
    assert Ash.get!(TeacherAssistant.Accounts.User, user.id, authorize?: false).role == :admin
  end

  test "an unknown identifier fails" do
    assert_raise Mix.Error, fn ->
      capture_io(fn -> Mix.Tasks.TeacherAssistant.MakeOperator.run(["nobody@example.com"]) end)
    end
  end
end
