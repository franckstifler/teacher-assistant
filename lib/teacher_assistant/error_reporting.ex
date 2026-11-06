defmodule TeacherAssistant.ErrorReporting do
  @moduledoc """
  Unhandled errors, grouped into issues by `ErrorTracker` in this app's database and
  shown to the operator at `/admin/errors`.

  ErrorTracker itself catches controller, LiveView and Oban job errors. This module
  adds what it leaves out:

    * the school and user an error happened for (`put_scope/1`), on every page and
      request that has a scope;
    * crashes of other processes (GenServers, Tasks), from their `:logger` crash
      reports — once only, when the crash was already reported by ErrorTracker;
    * an e-mail to the operators when an error is new or comes back after being
      resolved (`TeacherAssistant.Workers.ErrorAlert`);
    * its integrations attached again if a failure (the database down, say) made
      `:telemetry` detach them, instead of errors going unrecorded until a restart.

  Nothing here may raise: it runs inside other processes' failures.
  """

  alias TeacherAssistant.Scope

  @reported :teacher_assistant_error_reported
  @integrations [ErrorTracker.Integrations.Phoenix, ErrorTracker.Integrations.Oban]
  @reattach_after_ms 1_000

  @doc "Attaches the telemetry and `:logger` handlers. Called once, at application start."
  def attach do
    :telemetry.attach_many(
      __MODULE__,
      [
        [:error_tracker, :occurrence, :new],
        [:error_tracker, :error, :new],
        [:error_tracker, :error, :unresolved],
        [:phoenix, :router_dispatch, :start],
        [:telemetry, :handler, :failure]
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    :logger.add_handler(__MODULE__, __MODULE__.CrashHandler, %{level: :error})
  end

  @doc """
  Stamps the current process's errors with the school, the user and, while the operator
  acts as that user, the operator. Ids only, never names.
  """
  def put_scope(%Scope{} = scope) do
    ErrorTracker.set_context(%{
      "user_id" => scope.current_user && scope.current_user.id,
      "school_id" => scope.current_workspace && scope.current_workspace.id,
      "operator_id" => scope.impersonation && scope.impersonation.operator.id
    })

    :ok
  end

  def put_scope(_scope), do: :ok

  @scope_keys %{"user_id" => nil, "school_id" => nil, "operator_id" => nil}

  @doc false
  def handle_event(event, _measurements, metadata, _config) do
    handle(event, metadata)
  catch
    _kind, _reason -> :ok
  end

  # Remembers the error just stored, so the crash report the same process logs next
  # is not stored a second time (CrashHandler).
  defp handle([:error_tracker, :occurrence, :new], %{error: error, occurrence: occurrence}),
    do: Process.put(@reported, {error.kind, occurrence.reason})

  # One process serves every request of a kept-alive connection: a page with no scope
  # (sign-in, a check code) must not carry the previous request's school and user.
  # Runs before the pipeline, where `TeacherAssistantWeb.Plug.Scope` sets them again.
  defp handle([:phoenix, :router_dispatch, :start], _metadata),
    do: ErrorTracker.set_context(@scope_keys)

  defp handle([:error_tracker, :error, :new], %{error: error}), do: alert(error, false)

  # `occurrence: nil` is the operator reopening it by hand: no e-mail for that.
  defp handle([:error_tracker, :error, :unresolved], %{error: error, occurrence: %{}}),
    do: alert(error, true)

  defp handle([:telemetry, :handler, :failure], %{handler_id: id}) when id in @integrations do
    Task.start(fn ->
      Process.sleep(@reattach_after_ms)
      id.attach()
    end)
  end

  defp handle(_event, _metadata), do: :ok

  defp alert(%{muted: true}, _reopened?), do: :ok

  defp alert(error, reopened?) do
    %{"error_id" => error.id, "reopened" => reopened?}
    |> TeacherAssistant.Workers.ErrorAlert.new()
    |> Oban.insert()
  end

  @doc false
  # Whether this process's last stored error is `exception`, forgetting it either way.
  def already_reported?(exception) do
    Process.delete(@reported) == {to_string(exception.__struct__), Exception.message(exception)}
  end
end
