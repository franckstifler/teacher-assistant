defmodule TeacherAssistantWeb.Admin.TelegramTestButtonTest do
  # Sets the Telegram config for the whole node: not async.
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import TeacherAssistant.TelegramHelpers

  alias TeacherAssistant.TeacherFixtures

  defp console(conn) do
    op = TeacherFixtures.admin_user_fixture()

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> put_user_in_session(op)
    |> live(~p"/admin")
  end

  test "without Telegram set up, the panel says so and offers no test", %{conn: conn} do
    {:ok, view, _html} = console(conn)
    assert has_element?(view, "#telegram-off", "Non configurées")
    refute has_element?(view, "#telegram-test")
  end

  test "the operator sends a test message and is told it went", %{conn: conn} do
    set_up_telegram()
    stub_telegram()
    {:ok, view, _html} = console(conn)

    view |> element("#telegram-test") |> render_click()
    render_async(view)

    assert_received {:telegram, _, %{"text" => "Scolaka : les alertes Telegram fonctionnent."}}
    assert render(view) =~ "Message test envoyé sur Telegram."
  end

  test "a chat not found names the variable to fix", %{conn: conn} do
    set_up_telegram()
    stub_telegram(400, %{"ok" => false, "description" => "Bad Request: chat not found"})
    {:ok, view, _html} = console(conn)

    view |> element("#telegram-test") |> render_click()
    render_async(view)

    assert render(view) =~ "chat introuvable, vérifiez TELEGRAM_CHAT_ID"
  end

  test "a refused token names the variable to fix", %{conn: conn} do
    set_up_telegram()
    stub_telegram(401, %{"ok" => false, "description" => "Unauthorized"})
    {:ok, view, _html} = console(conn)

    view |> element("#telegram-test") |> render_click()
    render_async(view)

    assert render(view) =~ "jeton du bot refusé, vérifiez TELEGRAM_BOT_TOKEN"
  end

  test "any other refusal shows Telegram's reason", %{conn: conn} do
    set_up_telegram()

    stub_telegram(403, %{"ok" => false, "description" => "Forbidden: bot was blocked by the user"})

    {:ok, view, _html} = console(conn)

    view |> element("#telegram-test") |> render_click()
    render_async(view)

    assert render(view) =~ "Telegram a refusé le message : Forbidden: bot was blocked by the user"
  end
end
