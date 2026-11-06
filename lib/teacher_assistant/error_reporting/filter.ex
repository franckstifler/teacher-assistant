defmodule TeacherAssistant.ErrorReporting.Filter do
  @moduledoc """
  What an error keeps of its context: where it happened and for whom, as ids, never
  what was typed or sent. ErrorTracker's integrations also collect request params,
  headers, the query string and IP, LiveView params and event params, and Oban job
  args, which here are pupils' marks, names, phone numbers and fees: an allowlist
  drops all of it, including whatever a later ErrorTracker release adds.
  """
  @behaviour ErrorTracker.Filter

  @kept ~w(
    request.method request.path
    live_view.view live_view.event live_view.component
    job.worker job.queue job.attempt job.id state
    user_id school_id operator_id process
  )

  @impl true
  def sanitize(context) do
    # Keys come as strings or atoms (the Oban integration's `state`).
    context = Map.new(context, fn {key, value} -> {to_string(key), value} end)
    kept = Map.take(context, @kept)

    # The LiveView's URL without its query string (searches, filters).
    case context do
      %{"live_view.uri" => uri} when is_binary(uri) ->
        Map.put(kept, "live_view.path", URI.parse(uri).path)

      _ ->
        kept
    end
  end
end
