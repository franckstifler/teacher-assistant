defmodule TeacherAssistantWeb.Admin.ErrorsLiveTest do
  # ErrorTracker is turned on for the whole node: not async.
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  setup do
    Application.put_env(:error_tracker, :enabled, true)
    on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)
  end

  defp signed_in(conn, user),
    do:
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(user)

  defp report(message) do
    raise message
  rescue
    e -> ErrorTracker.report(e, __STACKTRACE__)
  end

  test "the operator sees the errors, from the console's menu", %{conn: conn} do
    %{error: error} = report("a page crashed")
    conn = signed_in(conn, TeacherFixtures.admin_user_fixture())

    {:ok, overview, _html} = live(conn, ~p"/admin")
    assert has_element?(overview, "#nav-admin-errors[href='/admin/errors']")
    assert has_element?(overview, "#attention-errors", "1 erreur à corriger")
    assert has_element?(overview, "#system-open-errors", "1")

    {:ok, _view, html} = live(conn, ~p"/admin/errors")
    assert html =~ "a page crashed"

    {:ok, _view, html} = live(conn, ~p"/admin/errors/#{error.id}")
    assert html =~ "a page crashed"
  end

  test "a muted error is not counted as open", %{conn: conn} do
    %{error: error} = report("known noise")
    {:ok, _} = error |> TeacherAssistant.Repo.reload!() |> ErrorTracker.mute()

    {:ok, overview, _html} =
      live(signed_in(conn, TeacherFixtures.admin_user_fixture()), ~p"/admin")

    refute has_element?(overview, "#attention-errors")
    assert has_element?(overview, "#system-open-errors", "0")
  end

  test "a school member is refused, a visitor sent to sign in", %{conn: conn} do
    %{head_user: head} = TeacherFixtures.setup_complete_school_fixture()

    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in(conn, head), ~p"/admin/errors")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/admin/errors")
  end
end
