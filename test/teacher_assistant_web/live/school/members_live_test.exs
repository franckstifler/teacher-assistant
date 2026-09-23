defmodule TeacherAssistantWeb.School.MembersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  defp enter_school(conn, school) do
    get(conn, ~p"/workspaces/select/#{school.id}")
  end

  test "head sees members, can invite, and sees the pending invitation", %{
    conn: conn,
    actor: user
  } do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Membres"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
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
    {:ok, school} = Organization.create_school(head, %{name: "Lycée Gate"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, member)

    conn = conn |> log_in_user(member) |> get(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#members-table")
    refute has_element?(view, "#invite-form")
  end

  test "invite form includes the employment-type options", %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Emploi"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    html = render(view)
    assert html =~ "Titulaire"
    assert html =~ "Contractuel"
    assert html =~ "Vacataire"
  end

  test "head can set a member's employment type", %{conn: conn, actor: head} do
    {:ok, school} = Organization.create_school(head, %{name: "Lycée Statut"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, member)

    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    membership =
      school
      |> Accounts.list_members()
      |> Enum.find(&(&1.user_id == member.id))

    view
    |> element("#member-status-form-#{membership.id}")
    |> render_change(%{"status" => "titulaire"})

    assert has_element?(view, "#member-row-#{membership.id}", "Titulaire")

    reloaded =
      school
      |> Accounts.list_members()
      |> Enum.find(&(&1.id == membership.id))

    assert reloaded.status == :titulaire
  end

  test "non-head cannot change employment type", %{conn: conn, actor: head} do
    {:ok, school} = Organization.create_school(head, %{name: "Lycée Statut Gate"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, member)

    conn = conn |> log_in_user(member) |> get(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    membership =
      school
      |> Accounts.list_members()
      |> Enum.find(&(&1.user_id == member.id))

    refute has_element?(view, "#member-status-form-#{membership.id}")

    render_change(view, "set_status", %{"id" => membership.id, "status" => "titulaire"})

    reloaded =
      school
      |> Accounts.list_members()
      |> Enum.find(&(&1.id == membership.id))

    assert reloaded.status == nil
  end
end
