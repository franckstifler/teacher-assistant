defmodule TeacherAssistant.Workers.TelegramAlertTest do
  # Sets the Telegram config and turns ErrorTracker on for the whole node: not async.
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  alias TeacherAssistant.{Telegram, TeacherFixtures}
  alias TeacherAssistant.Workers.TelegramAlert

  @test_config Application.compile_env(:teacher_assistant, Telegram, [])

  defp set_up_telegram do
    Application.put_env(
      :teacher_assistant,
      Telegram,
      Keyword.merge(@test_config, bot_token: "123:ABC", chat_id: "-1001")
    )

    on_exit(fn -> Application.put_env(:teacher_assistant, Telegram, @test_config) end)
  end

  # The messages Telegram would receive, sent to the test process.
  defp stub_telegram(status \\ 200, body \\ %{"ok" => true}) do
    test = self()

    Req.Test.stub(Telegram, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test, {:telegram, conn.request_path, Jason.decode!(raw)})
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  defp report(message) do
    raise message
  rescue
    e -> ErrorTracker.report(e, __STACKTRACE__)
  end

  describe "without Telegram set up" do
    test "a new school and an error queue nothing" do
      Application.put_env(:error_tracker, :enabled, true)
      on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)

      TeacherFixtures.school_fixture()
      report("quiet")

      refute_enqueued(worker: TelegramAlert)
    end
  end

  describe "with Telegram set up" do
    setup do
      set_up_telegram()
      stub_telegram()
      :ok
    end

    test "a school that signs up is announced with its town and admin link" do
      %{workspace: workspace} = TeacherFixtures.school_fixture(%{name: "Lycée de Bonabéri"})
      args = %{"event" => "new_school", "workspace_id" => workspace.id}
      assert_enqueued(worker: TelegramAlert, args: args)

      assert :ok = perform_job(TelegramAlert, args)

      assert_received {:telegram, "/bot123:ABC/sendMessage",
                       %{"chat_id" => "-1001", "text" => text}}

      assert text =~ "Nouvelle école à vérifier : Lycée de Bonabéri"
      assert text =~ "/admin/schools/#{workspace.id}"
    end

    test "an error is announced by kind, place and link, never by its message" do
      Application.put_env(:error_tracker, :enabled, true)
      on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)

      %{error: error} = report("Note de MBARGA Jean : 25")
      args = %{"event" => "error", "error_id" => error.id, "reopened" => false}
      assert_enqueued(worker: TelegramAlert, args: args)

      assert :ok = perform_job(TelegramAlert, args)

      assert_received {:telegram, _path, %{"text" => text}}
      assert text =~ "Nouvelle erreur : RuntimeError"
      assert text =~ "/admin/errors/#{error.id}"
      refute text =~ "MBARGA"
    end

    test "a school or error gone in the meantime sends nothing" do
      assert :ok =
               perform_job(TelegramAlert, %{
                 "event" => "new_school",
                 "workspace_id" => Ash.UUID.generate()
               })

      assert :ok =
               perform_job(TelegramAlert, %{
                 "event" => "error",
                 "error_id" => -1,
                 "reopened" => true
               })

      refute_received {:telegram, _, _}
    end

    test "a refusal from Telegram fails the job with its description, not the token" do
      stub_telegram(400, %{"ok" => false, "description" => "Bad Request: chat not found"})
      %{workspace: workspace} = TeacherFixtures.school_fixture()

      assert {:error, {400, "Bad Request: chat not found"} = reason} =
               perform_job(TelegramAlert, %{
                 "event" => "new_school",
                 "workspace_id" => workspace.id
               })

      refute inspect(reason) =~ "ABC"
    end
  end

  test "Telegram needs both the token and the chat id" do
    refute Telegram.configured?()
    set_up_telegram()
    assert Telegram.configured?()

    Application.put_env(
      :teacher_assistant,
      Telegram,
      Keyword.put(@test_config, :bot_token, "1:A")
    )

    refute Telegram.configured?()
  end
end
