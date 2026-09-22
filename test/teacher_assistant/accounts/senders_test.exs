defmodule TeacherAssistant.Accounts.SendersTest do
  use TeacherAssistant.DataCase, async: true
  import Swoosh.TestAssertions
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.TeacherFixtures

  test "requesting a password reset delivers an email with a reset link" do
    user = TeacherFixtures.user_fixture(%{email: "reset-me@example.com"})

    User
    |> Ash.Query.for_read(:request_password_reset_with_password, %{email: to_string(user.email)})
    |> Ash.read!(authorize?: false)

    assert_email_sent(fn email ->
      assert {_, "reset-me@example.com"} = hd(email.to)
      assert email.text_body =~ "/password-reset/"
    end)
  end

  test "requesting a magic link delivers an email with a sign-in link" do
    user = TeacherFixtures.user_fixture(%{email: "magic-me@example.com"})

    User
    |> Ash.ActionInput.for_action(:request_magic_link, %{email: to_string(user.email)})
    |> Ash.run_action!(authorize?: false)

    assert_email_sent(fn email ->
      assert {_, "magic-me@example.com"} = hd(email.to)
      assert email.text_body =~ "/magic_link/"
    end)
  end
end
