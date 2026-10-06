defmodule TeacherAssistantWeb.NotificationBellTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Notifications

  setup :register_and_log_in_user

  defp remind(scope, user, subject \\ "Maths") do
    Notifications.deliver(
      scope,
      :entry_reminder,
      [user.id],
      %{subject: subject, class: "3e A", sequence: 2},
      "/school/settings"
    )
  end

  test "the bell counts unread notices and updates live", %{conn: conn, scope: scope, actor: head} do
    {:ok, view, _} = live(conn, ~p"/school")
    assert has_element?(view, "#notification-bell")
    refute has_element?(view, "#notification-bell-count")

    remind(scope, head)

    assert has_element?(view, "#notification-bell-count", "1")
    assert has_element?(view, "#notification-bell-mobile .badge", "1")

    assert has_element?(
             view,
             "#notification-bell li",
             "Saisie en retard : Maths · 3e A · Séquence 2"
           )

    assert has_element?(view, ~s|#bell-see-all[href="/school/notifications"]|)
  end

  test "opening a notice from the bell marks it read and follows its link",
       %{conn: conn, scope: scope, actor: head} do
    remind(scope, head)
    [n] = Notifications.bell(scope).latest
    {:ok, view, _} = live(conn, ~p"/school")

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             view |> element("#bell-item-#{n.id}") |> render_click()

    assert %{unread: 0} = Notifications.bell(scope)
  end

  test "« Tout marquer comme lu » clears the count", %{conn: conn, scope: scope, actor: head} do
    remind(scope, head, "Maths")
    remind(scope, head, "SVT")
    {:ok, view, _} = live(conn, ~p"/school")
    assert has_element?(view, "#notification-bell-count", "2")

    view |> element("#bell-read-all") |> render_click()
    refute has_element?(view, "#notification-bell-count")
    assert %{unread: 0} = Notifications.bell(scope)
  end

  test "a forged open event for someone else's notice changes nothing",
       %{conn: conn, scope: scope} do
    other = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope)
    remind(scope, other.current_user)
    [n] = Notifications.bell(other).latest
    {:ok, view, _} = live(conn, ~p"/school")

    render_hook(view, "notification:open", %{"id" => n.id})
    assert %{unread: 1} = Notifications.bell(other)
  end
end
