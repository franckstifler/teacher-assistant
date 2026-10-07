defmodule TeacherAssistant.Accounts.Memberships do
  @moduledoc """
  Create or reactivate a user's membership in a school. Shared by invitation
  acceptance (system call, `authorize?: false`) and by a head adding a phone
  account (`scope:`, policy-checked). `opts` go to every Ash call and must
  carry the school as tenant (directly or through the scope).
  """
  require Ash.Query
  alias TeacherAssistant.Accounts.SchoolMembership

  def ensure_active(user_id, roles, status, opts) do
    SchoolMembership
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read_one(opts)
    |> case do
      {:ok, %SchoolMembership{active: true}} ->
        :ok

      {:ok, %SchoolMembership{} = m} ->
        m
        |> Ash.Changeset.for_update(:update, %{active: true, roles: roles, status: status}, opts)
        |> Ash.update()
        |> ok()

      {:ok, nil} ->
        SchoolMembership
        |> Ash.Changeset.for_create(
          :create,
          %{user_id: user_id, roles: roles, status: status},
          opts
        )
        |> Ash.create()
        |> ok()

      {:error, error} ->
        {:error, error}
    end
  end

  defp ok({:ok, _}), do: :ok
  defp ok({:error, error}), do: {:error, error}
end
