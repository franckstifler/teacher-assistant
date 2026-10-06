defmodule TeacherAssistantWeb.School.NotificationsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Notifications, TeacherFixtures}

  setup :register_and_log_in_user

  defp remind(scope, user, subject) do
    Notifications.deliver(
      scope,
      :entry_reminder,
      [user.id],
      %{subject: subject, class: "3e A", sequence: 1},
      "/school/settings"
    )
  end

  test "newest first, unread marked; opening one follows its link",
       %{conn: conn, scope: scope, actor: head} do
    remind(scope, head, "Maths")
    remind(scope, head, "SVT")
    [svt, maths] = Notifications.inbox(scope, 1).results
    {:ok, _} = Notifications.open(scope, maths.id)

    {:ok, view, html} = live(conn, ~p"/school/notifications")
    assert html =~ "Notifications"
    assert has_element?(view, "#notification-#{svt.id}[data-unread]", "SVT")
    assert has_element?(view, "#notification-#{maths.id}", "Maths")
    refute has_element?(view, "#notification-#{maths.id}[data-unread]")
    assert html =~ ~r/SVT.*Maths/s

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             view |> element("#notification-#{svt.id}") |> render_click()

    assert %{unread: 0} = Notifications.bell(scope)
  end

  test "« Tout marquer comme lu » clears every unread mark",
       %{conn: conn, scope: scope, actor: head} do
    remind(scope, head, "Maths")
    remind(scope, head, "SVT")
    {:ok, view, _} = live(conn, ~p"/school/notifications")

    view |> element("#read-all") |> render_click()
    refute has_element?(view, "[data-unread]")
    refute has_element?(view, "#notification-bell-count")
  end

  test "a teacher sees only their own notices",
       %{conn: conn, scope: scope, actor: head, workspace: ws} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    remind(scope, head, "Maths")
    remind(scope, teacher.current_user, "Anglais")

    conn =
      conn
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    {:ok, view, _} = live(conn, ~p"/school/notifications")
    list = view |> element("#notifications") |> render()
    assert list =~ "Anglais"
    refute list =~ "Maths"
  end

  test "an empty inbox says so; more than a page shows the pager",
       %{conn: conn, scope: scope, actor: head} do
    {:ok, view, _} = live(conn, ~p"/school/notifications")
    assert has_element?(view, "#notifications-empty")

    for n <- 1..(Notifications.page_size() + 1), do: remind(scope, head, "S#{n}")
    {:ok, view, _} = live(conn, ~p"/school/notifications?page=2")
    assert has_element?(view, "#notifications-pager")
    list = view |> element("#notifications") |> render()
    assert list =~ "S1 ·"
    refute list =~ "S31 ·"
  end
end
