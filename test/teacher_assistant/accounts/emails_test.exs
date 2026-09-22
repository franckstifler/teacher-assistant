defmodule TeacherAssistant.Accounts.EmailsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Emails

  test "school_invitation/3 addresses the invitee, sets from + subject, embeds the URL" do
    url = "http://localhost:4000/schools/invitations/tok123"
    email = Emails.school_invitation("prof@example.com", "Lycée de Test", url)

    assert {_, "prof@example.com"} = hd(email.to)
    assert {_name, _addr} = email.from
    assert email.subject not in [nil, ""]
    assert email.text_body =~ url
    assert email.html_body =~ url
  end

  test "password_reset/2 embeds the reset URL" do
    user = %{email: "u@example.com"}
    email = Emails.password_reset(user, "http://localhost:4000/reset/abc")
    assert email.text_body =~ "http://localhost:4000/reset/abc"
  end
end
