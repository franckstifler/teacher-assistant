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

  test "at most three reset or magic-link emails per account per hour" do
    user = TeacherFixtures.user_fixture(%{email: "flood-me@example.com"})

    request_reset = fn ->
      User
      |> Ash.Query.for_read(:request_password_reset_with_password, %{
        email: to_string(user.email)
      })
      |> Ash.read!(authorize?: false)
    end

    request_magic = fn ->
      User
      |> Ash.ActionInput.for_action(:request_magic_link, %{email: to_string(user.email)})
      |> Ash.run_action!(authorize?: false)
    end

    request_reset.()
    request_magic.()
    request_reset.()
    for _ <- 1..3, do: assert_email_sent()

    request_magic.()
    request_reset.()
    refute_email_sent()
  end

  test "a refused reset email is logged; the request still answers the same" do
    user = TeacherFixtures.user_fixture(%{email: "lost@undeliverable.test"})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        User
        |> Ash.Query.for_read(:request_password_reset_with_password, %{
          email: to_string(user.email)
        })
        |> Ash.read!(authorize?: false)
      end)

    assert log =~ "password reset email to user #{user.id} not sent"
    refute_email_sent()
  end
end
