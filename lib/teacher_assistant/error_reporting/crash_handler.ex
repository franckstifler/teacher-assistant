defmodule TeacherAssistant.ErrorReporting.CrashHandler do
  @moduledoc """
  A `:logger` handler that stores process crashes (GenServers, Tasks) in ErrorTracker,
  from the `crash_reason` of their crash reports. A crash ErrorTracker already stored
  in the same process (a LiveView or a request) is skipped.

  It runs inside the process that logged, often a dying one, so it never raises (a
  raising handler is removed by `:logger`) and never runs inside itself: a failure
  while storing (the database down) may log, and that log must not be stored again.
  """

  alias TeacherAssistant.ErrorReporting

  @in_handler :teacher_assistant_crash_handler

  @doc false
  def log(%{meta: %{crash_reason: {reason, stack}} = meta}, _config) when is_list(stack) do
    if Process.get(@in_handler), do: :ok, else: guarded(fn -> report(reason, stack, meta) end)
  end

  def log(_event, _config), do: :ok

  defp guarded(fun) do
    Process.put(@in_handler, true)
    fun.()
    :ok
  catch
    _kind, _reason -> :ok
  after
    Process.delete(@in_handler)
  end

  defp report(reason, stack, meta) do
    context = %{"process" => inspect(meta[:registered_name] || meta[:pid])}

    cond do
      not is_exception(reason) -> ErrorTracker.report({:exit, reason}, stack, context)
      ErrorReporting.already_reported?(reason) -> :ok
      true -> ErrorTracker.report(reason, stack, context)
    end
  end
end
