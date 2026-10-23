defmodule TeacherAssistant.Accounts.AccessCache do
  @moduledoc """
  Remembers, for 5 seconds, the two facts every policy check reads: a user's active
  roles in a school (`Checks.SchoolRole`) and whether a school is verified
  (`Checks.SchoolVerified`). One page or click runs dozens of checks with the same
  answer; without this each one is a database read.

  Writes that change a fact forget it at once (`SchoolMembership` and `SchoolProfile`
  changes call `forget_member/2` / `forget_school/1`), so on one node a removed member
  is refused on their next call. The 5 seconds bound how long another node, or a read
  that raced a write, can keep an old answer.

  One ETS table per node, owned by this process; entries expire lazily.
  """
  use GenServer

  @table __MODULE__
  @ttl_ms 5_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc "The user's active roles in the school (`nil` if not an active member); `read` on a miss."
  def roles(user_id, workspace_id, read), do: fetch({:roles, user_id, workspace_id}, read)

  @doc "Whether the school is verified; `read` on a miss."
  def verified?(workspace_id, read), do: fetch({:verified, workspace_id}, read)

  @doc "Forgets a user's roles in a school (their membership changed)."
  def forget_member(user_id, workspace_id), do: forget({:roles, user_id, workspace_id})

  @doc "Forgets whether a school is verified (its profile's status changed)."
  def forget_school(workspace_id), do: forget({:verified, workspace_id})

  defp fetch(key, read) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, at}] when now - at < @ttl_ms ->
        value

      _ ->
        value = read.()
        :ets.insert(@table, {key, value, now})
        value
    end
  end

  defp forget(key) do
    :ets.delete(@table, key)
    :ok
  end
end
