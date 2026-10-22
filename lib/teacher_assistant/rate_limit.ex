defmodule TeacherAssistant.RateLimit do
  @moduledoc """
  Per-node counters (ETS) that cap how often one identity can try something:
  signing in, asking for a reset or magic-link email, checking a receipt number.
  Keys are what is being guessed at (an account, a receipt number), not an IP
  address — behind the TLS proxy every request comes from the proxy.
  """
  use Hammer, backend: :ets

  @doc "Counts one attempt at `key`; `true` while at most `limit` happened in the last `scale_ms`."
  def allow?(key, limit, scale_ms) do
    match?({:allow, _count}, hit(key, scale_ms, limit))
  end
end
