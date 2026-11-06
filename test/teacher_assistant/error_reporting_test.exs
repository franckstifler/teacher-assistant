defmodule TeacherAssistant.ErrorReportingTest do
  # ErrorTracker is turned on for the whole node: not async.
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  alias TeacherAssistant.ErrorReporting
  alias TeacherAssistant.ErrorReporting.{CrashHandler, Filter}
  alias TeacherAssistant.{Repo, Scope, TeacherFixtures}
  alias TeacherAssistant.Workers.ErrorAlert

  setup do
    Application.put_env(:error_tracker, :enabled, true)
    on_exit(fn -> Application.put_env(:error_tracker, :enabled, false) end)
  end

  defp raised(message) do
    raise message
  rescue
    e -> {e, __STACKTRACE__}
  end

  defp report(message, context \\ %{}) do
    {e, stack} = raised(message)
    ErrorTracker.report(e, stack, context)
  end

  defp errors, do: Repo.all(ErrorTracker.Error)

  describe "Filter" do
    test "keeps where and for whom, drops what was typed or sent" do
      context = %{
        "request.method" => "POST",
        "request.path" => "/school/marks",
        "request.params" => %{"mark" => "12"},
        "request.headers" => %{"user-agent" => "x"},
        "request.query" => "q=Ngono",
        "request.ip" => "1.2.3.4",
        "live_view.view" => TeacherAssistantWeb.Admin.OverviewLive,
        "live_view.uri" => "https://app.cm/school/students?q=Ngono",
        "live_view.params" => %{"q" => "Ngono"},
        "live_view.event" => "save",
        "live_view.event_params" => %{"name" => "Ngono"},
        "job.worker" => "W",
        "job.args" => %{"phone" => "699"},
        :state => :discard,
        "user_id" => "u1",
        "school_id" => "s1"
      }

      assert Filter.sanitize(context) == %{
               "request.method" => "POST",
               "request.path" => "/school/marks",
               "live_view.view" => TeacherAssistantWeb.Admin.OverviewLive,
               "live_view.path" => "/school/students",
               "live_view.event" => "save",
               "job.worker" => "W",
               "state" => :discard,
               "user_id" => "u1",
               "school_id" => "s1"
             }
    end
  end

  test "an error carries the school, the user and the acting operator" do
    scope = %Scope{
      current_user: %{id: "user-1"},
      current_workspace: %{id: "school-1"},
      impersonation: %{operator: %{id: "operator-1"}}
    }

    ErrorReporting.put_scope(scope)
    occurrence = report("boom")

    assert %{"user_id" => "user-1", "school_id" => "school-1", "operator_id" => "operator-1"} =
             occurrence.context
  end

  test "each request starts without the previous request's school and user" do
    ErrorReporting.put_scope(%Scope{current_user: %{id: "user-1"}, current_workspace: %{id: "s"}})
    ErrorReporting.handle_event([:phoenix, :router_dispatch, :start], %{}, %{}, nil)

    occurrence = report("public page")
    assert %{"user_id" => nil, "school_id" => nil} = occurrence.context
  end

  describe "alerts" do
    test "a new error queues one e-mail; its next occurrences none" do
      %{error: error} = report("first")
      assert_enqueued(worker: ErrorAlert, args: %{"error_id" => error.id, "reopened" => false})

      report("first")
      assert [_] = all_enqueued(worker: ErrorAlert)
    end

    test "an error back after being resolved queues an e-mail; a muted one doesn't" do
      %{error: error} = report("again")
      {:ok, _} = ErrorTracker.resolve(Repo.reload!(error))
      Repo.delete_all(Oban.Job)

      report("again")
      assert_enqueued(worker: ErrorAlert, args: %{"error_id" => error.id, "reopened" => true})

      {:ok, _} = error |> Repo.reload!() |> ErrorTracker.resolve()
      {:ok, _} = error |> Repo.reload!() |> ErrorTracker.mute()
      Repo.delete_all(Oban.Job)

      report("again")
      refute_enqueued(worker: ErrorAlert)
    end

    test "the e-mail goes to each operator with an address, with a link to the error" do
      operator = TeacherFixtures.admin_user_fixture()
      _teacher = TeacherFixtures.user_fixture()
      %{error: error} = report("mail me")

      assert :ok = perform_job(ErrorAlert, %{"error_id" => error.id, "reopened" => false})

      assert_email_sent(fn email ->
        assert email.to == [{"", to_string(operator.email)}]
        assert email.subject == "Nouvelle erreur : RuntimeError"
        assert email.text_body =~ "mail me"
        assert email.text_body =~ "/admin/errors/#{error.id}"
      end)

      refute_email_sent()
    end

    test "an error deleted in the meantime sends nothing" do
      assert :ok = perform_job(ErrorAlert, %{"error_id" => -1, "reopened" => false})
      refute_email_sent()
    end
  end

  describe "crashes of other processes" do
    test "a crashing GenServer is stored with its exception" do
      {:ok, pid} = Agent.start(fn -> nil end)

      capture_log(fn ->
        ref = Process.monitor(pid)
        Agent.cast(pid, fn _ -> raise ArgumentError, "agent crash" end)
        assert_receive {:DOWN, ^ref, _, _, _}
        # The crash report is handled in the dying process, before it exits.
        Process.sleep(50)
      end)

      assert [%{kind: "Elixir.ArgumentError", reason: "agent crash"}] = errors()
    end

    test "a crash already stored by ErrorTracker in the same process is not stored twice" do
      {e, stack} = raised("once")
      %{error: error} = ErrorTracker.report(e, stack)

      CrashHandler.log(%{level: :error, meta: %{crash_reason: {e, stack}}}, %{})

      assert [%{id: id}] = errors()
      assert id == error.id
      assert [_] = Repo.all(ErrorTracker.Occurrence)
    end

    test "an exit reason that is not an exception is stored too" do
      CrashHandler.log(%{level: :error, meta: %{crash_reason: {:boom, []}}}, %{})
      assert [%{kind: "exit", reason: "boom"}] = errors()
    end
  end

  test "an ErrorTracker integration detached by a failure is attached again" do
    events = [:phoenix, :router_dispatch, :exception]
    on_exit(fn -> ErrorTracker.Integrations.Phoenix.attach() end)
    :ok = :telemetry.detach(ErrorTracker.Integrations.Phoenix)

    ErrorReporting.handle_event(
      [:telemetry, :handler, :failure],
      %{},
      %{
        handler_id: ErrorTracker.Integrations.Phoenix
      },
      nil
    )

    Process.sleep(1_200)

    assert Enum.any?(
             :telemetry.list_handlers(events),
             &(&1.id == ErrorTracker.Integrations.Phoenix)
           )
  end
end
