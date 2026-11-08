defmodule TeacherAssistant.TelegramHelpers do
  @moduledoc """
  Telegram in tests: a bot token and chat id set for the test (process-wide: only in
  non-async tests), and a stub that forwards each message to the test process as
  `{:telegram, path, body}` instead of calling the API.
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias TeacherAssistant.Telegram

  @test_config Application.compile_env(:teacher_assistant, Telegram, [])

  def set_up_telegram(overrides \\ [bot_token: "123:ABC", chat_id: "-1001"]) do
    Application.put_env(:teacher_assistant, Telegram, Keyword.merge(@test_config, overrides))
    on_exit(fn -> Application.put_env(:teacher_assistant, Telegram, @test_config) end)
  end

  def stub_telegram(status \\ 200, body \\ %{"ok" => true}) do
    test = self()

    Req.Test.stub(Telegram, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test, {:telegram, conn.request_path, Jason.decode!(raw)})
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end
end
