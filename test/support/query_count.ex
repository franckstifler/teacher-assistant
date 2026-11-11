defmodule TeacherAssistant.QueryCount do
  @moduledoc """
  Counts the Repo queries a function runs, from this process or the processes it
  starts (a LiveView names the test in `$callers`): the total, and how many match each
  of `needles` (substrings of the SQL, such as `~s(FROM "marks")`). From the A3
  dashboard budget test; shared since A8.
  """

  @doc "`{result, total, %{needle => count}}`."
  def count(fun, needles \\ []) do
    table = :ets.new(:query_count, [:public, :set])
    :ets.insert(table, {:total, 0})
    Enum.each(needles, &:ets.insert(table, {&1, 0}))
    handler = {__MODULE__, make_ref()}

    # A module function, not a closure: telemetry runs a closure handler once per
    # attached closure of the same shape, so two concurrent tests double each other.
    :telemetry.attach(handler, [:teacher_assistant, :repo, :query], &__MODULE__.handle_event/4, %{
      parent: self(),
      table: table,
      needles: needles
    })

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

  @doc false
  def handle_event(_event, _measurements, %{query: q}, %{
        parent: parent,
        table: table,
        needles: needles
      }) do
    if self() == parent or parent in List.wrap(Process.get(:"$callers")) do
      :ets.update_counter(table, :total, 1)
      for n <- needles, q =~ n, do: :ets.update_counter(table, n, 1)
    end

    :ok
  end
end
