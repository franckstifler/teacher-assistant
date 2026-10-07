defmodule TeacherAssistantWeb.Account.PasswordLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts

  setup :register_and_log_in_user

  defp phone_teacher(scope) do
    {:ok, %{user: user, temporary_password: pw}} =
      Accounts.add_member_by_phone(scope, %{
        name: "Awa Nji",
        phone: "677123456",
        roles: [:teacher]
      })

    {user, pw}
  end

  defp log_in_phone_teacher(conn, scope, school) do
    {user, _pw} = phone_teacher(scope)
    conn = conn |> log_in_user(user) |> Plug.Conn.put_session(:workspace_id, school.id)
    {conn, user}
  end

  test "a teacher with a temporary password is sent to /account/password", %{
    conn: conn,
    scope: scope,
    workspace: school
  } do
    {conn, _user} = log_in_phone_teacher(conn, scope, school)

    assert {:error, {:redirect, %{to: "/account/password"}}} = live(conn, ~p"/school")
  end

  test "print route redirects", %{conn: conn, scope: scope, workspace: school} do
    {conn, _user} = log_in_phone_teacher(conn, scope, school)

    conn = get(conn, ~p"/school/timetable/me/print")
    assert redirected_to(conn) == ~p"/account/password"
  end

  test "the screen names the person and their school", %{
    conn: conn,
    scope: scope,
    workspace: school
  } do
    {conn, _user} = log_in_phone_teacher(conn, scope, school)

    {:ok, _view, html} = live(conn, ~p"/account/password")

    assert html =~ "Awa Nji"
    assert html =~ "6 77 12 34 56"
    assert html =~ school.name
    assert html =~ "Choisissez votre mot de passe"
  end

  test "the checklist follows what is typed", %{conn: conn, scope: scope, workspace: school} do
    {conn, _user} = log_in_phone_teacher(conn, scope, school)
    {:ok, view, _html} = live(conn, ~p"/account/password")

    refute has_element?(view, "#check-length[data-met]")
    refute has_element?(view, "#check-match[data-met]")

    view
    |> form("#own-password-form", %{
      "form" => %{"password" => "my-own-pass", "password_confirmation" => "my-own"}
    })
    |> render_change()

    assert has_element?(view, "#check-length[data-met]")
    refute has_element?(view, "#check-match[data-met]")

    view
    |> form("#own-password-form", %{
      "form" => %{"password" => "my-own-pass", "password_confirmation" => "my-own-pass"}
    })
    |> render_change()

    assert has_element?(view, "#check-match[data-met]")
  end

  test "choosing a password lifts the gate", %{conn: conn, scope: scope, workspace: school} do
    {conn, user} = log_in_phone_teacher(conn, scope, school)

    {:ok, view, _html} = live(conn, ~p"/account/password")

    view
    |> form("#own-password-form", %{
      "form" => %{"password" => "my-own-pass", "password_confirmation" => "my-own-pass"}
    })
    |> render_submit()

    assert_redirect(view, ~p"/school")
    refute Ash.get!(Accounts.User, user.id, authorize?: false).must_change_password
  end

  test "mismatched confirmation shows an error", %{conn: conn, scope: scope, workspace: school} do
    {conn, user} = log_in_phone_teacher(conn, scope, school)
    {:ok, view, _html} = live(conn, ~p"/account/password")

    html =
      view
      |> form("#own-password-form", %{
        "form" => %{"password" => "my-own-pass", "password_confirmation" => "different"}
      })
      |> render_submit()

    assert html =~ "own-password-form"
    assert Ash.get!(Accounts.User, user.id, authorize?: false).must_change_password
  end

  test "a user without the flag is not redirected", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/school")
  end

  test "a user without the flag cannot open the change screen", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/school"}}} = live(conn, ~p"/account/password")
  end

  test "expired temporary password is refused", %{scope: scope} do
    {user, _pw} = phone_teacher(scope)

    Ash.Seed.update!(user, %{
      temporary_password_expires_at:
        DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second)
    })

    user = Ash.get!(Accounts.User, user.id, authorize?: false)

    conn =
      build_conn()
      |> init_test_session(%{})
      |> fetch_flash()
      |> TeacherAssistantWeb.AuthController.success({:phone, :sign_in}, user, "unused-token")

    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expir"
    refute get_session(conn, "user_token")
    refute get_session(conn, "user")
    refute get_session(conn, :user_id)
  end
end
