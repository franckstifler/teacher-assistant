defmodule TeacherAssistant.QueryCount do
  @moduledoc """
  Counts the Repo queries a function runs, from this process or the processes it
  starts (a LiveView names the test in `$callers`): the total, and how many match each
  of `needles` (substrings of the SQL, such as `~s(FROM "marks")`). From the A3
  dashboard budget test; shared since A8.
  """

  @doc "`{result, total, %{needle => count}}`."
  def count(fun, needles \\ []) do
    parent = self()
    table = :ets.new(:query_count, [:public, :set])
    :ets.insert(table, {:total, 0})
    Enum.each(needles, &:ets.insert(table, {&1, 0}))
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:teacher_assistant, :repo, :query],
      fn _e, _m, %{query: q}, _ ->
        if self() == parent or parent in List.wrap(Process.get(:"$callers")) do
          :ets.update_counter(table, :total, 1)
          for n <- needles, q =~ n, do: :ets.update_counter(table, n, 1)
        end
      end,
      nil
    )

    result =
      try do
        fun.()
      after
        :telemetry.detach(handler)
      end

    [{:total, total}] = :ets.lookup(table, :total)
    counts = Map.new(needles, fn n -> {n, :ets.lookup_element(table, n, 2)} end)
    :ets.delete(table)
    {result, total, counts}
  end
end
