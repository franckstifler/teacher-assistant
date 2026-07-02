defmodule TeacherAssistantWeb.School.MembersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  defp enter_school(conn, school) do
    get(conn, ~p"/workspaces/select/#{school.id}")
  end

  test "head sees members, can invite, and sees the pending invitation", %{
    conn: conn,
    actor: user
  } do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Membres"})
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#school-members")
    assert has_element?(view, "#members-table")
    assert has_element?(view, "#invite-form")

    view
    |> form("#invite-form", %{
      "invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}
    })
    |> render_submit()

    assert has_element?(view, "#invitations-list", "prof@example.com")
  end

  test "a non-head member does not see the invite form", %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Gate"})
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, member)

    conn = conn |> log_in_user(member) |> get(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#members-table")
    refute has_element?(view, "#invite-form")
  end
end
