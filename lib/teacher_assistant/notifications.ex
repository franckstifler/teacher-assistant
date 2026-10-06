defmodule TeacherAssistant.Notifications do
  @moduledoc """
  Spec KLM8: staff in-app notifications. `deliver/5` is the only way one is created —
  and the single place a future e-mail or SMS channel plugs into. The recipient reads
  them and marks them read. Every change is broadcast to the recipient on
  `"notifications:<user_id>"` as `:notifications_changed`.
  """
  require Ash.Query

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.{Notification, SchoolRole}
  alias TeacherAssistant.Scope

  @pubsub TeacherAssistant.PubSub
  @page_size 30
  @bell_size 8

  def page_size, do: @page_size

  def subscribe(user_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(user_id))

  @doc """
  One notification per recipient (duplicates dropped) in the scope's school, then a
  broadcast to each. `params` values become strings; `link` must be an app path.
  Callers pass recipients already without the acting user.
  """
  def deliver(%Scope{current_workspace: %{id: workspace_id}}, kind, recipient_ids, params, link) do
    link = app_path!(link)
    params = Map.new(params, fn {key, value} -> {to_string(key), to_string(value)} end)

    case Enum.uniq(recipient_ids) do
      [] ->
        :ok

      ids ->
        # The sanctioned bypass of `:deliver`'s forbid-all policy.
        %Ash.BulkResult{status: :success} =
          ids
          |> Enum.map(&%{recipient_user_id: &1, kind: kind, params: params, link: link})
          |> Ash.bulk_create(Notification, :deliver,
            tenant: workspace_id,
            authorize?: false,
            return_errors?: true
          )

        Enum.each(ids, &broadcast/1)
    end
  end

  @doc "The header bell: unread count and the newest notices."
  def bell(%Scope{} = scope) do
    latest =
      Notification
      |> Ash.Query.for_read(:inbox, %{}, scope: scope)
      |> Ash.Query.limit(@bell_size)
      |> Ash.read!()

    %{unread: unread_count(scope), latest: latest}
  end

  @doc "One page (from 1) of the scope's notices, newest first, with the total count."
  def inbox(%Scope{} = scope, page) when is_integer(page) and page > 0 do
    Notification
    |> Ash.Query.for_read(:inbox, %{}, scope: scope)
    |> Ash.read!(page: [limit: @page_size, offset: (page - 1) * @page_size, count: true])
  end

  @doc "Marks the scope's notice `id` read and returns its link; `:error` when not theirs."
  def open(%Scope{} = scope, id) do
    with {:ok, %Notification{} = n} <- Ash.get(Notification, id, scope: scope),
         {:ok, n} <- mark_read(scope, n) do
      {:ok, n.link}
    else
      _ -> :error
    end
  end

  def mark_all_read(%Scope{current_user: %{id: user_id}} = scope) do
    Notification
    |> Ash.Query.filter(recipient_user_id == ^user_id and is_nil(read_at))
    |> Ash.bulk_update!(:mark_read, %{}, scope: scope, strategy: [:atomic, :stream])

    broadcast(user_id)
  end

  @doc "The active members who decide corrections (Proviseur, Censeur)."
  def admin_ids(%Scope{} = scope) do
    admin = SchoolRole.axis(:admin)
    for m <- Accounts.list_members(scope), Enum.any?(m.roles, &(&1 in admin)), do: m.user_id
  end

  defp unread_count(scope),
    do: Notification |> Ash.Query.filter(is_nil(read_at)) |> Ash.count!(scope: scope)

  # The first read time is kept.
  defp mark_read(_scope, %Notification{read_at: %DateTime{}} = n), do: {:ok, n}

  defp mark_read(scope, n) do
    with {:ok, n} <- n |> Ash.Changeset.for_update(:mark_read, %{}, scope: scope) |> Ash.update() do
      broadcast(n.recipient_user_id)
      {:ok, n}
    end
  end

  defp topic(user_id), do: "notifications:#{user_id}"

  defp broadcast(user_id),
    do: Phoenix.PubSub.broadcast(@pubsub, topic(user_id), :notifications_changed)

  defp app_path!("//" <> _ = link), do: raise(ArgumentError, "not an app path: #{inspect(link)}")
  defp app_path!("/" <> _ = link), do: link
  defp app_path!(link), do: raise(ArgumentError, "not an app path: #{inspect(link)}")
end
