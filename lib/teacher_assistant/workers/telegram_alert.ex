defmodule TeacherAssistant.Workers.TelegramAlert do
  @moduledoc """
  Tells the operators on Telegram (`TeacherAssistant.Telegram`) that a school has
  just signed up and waits to be verified, or that an error is new or back
  (alongside `TeacherAssistant.Workers.ErrorAlert`'s e-mail). Nothing is queued
  while Telegram is not set up.

  Pupils are minors and Telegram is a third party: an error's message is not sent,
  only its kind, where it happened and the link to `/admin/errors`.
  """
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 3600]
  use TeacherAssistantWeb, :verified_routes
  use Gettext, backend: TeacherAssistantWeb.Gettext

  require Ash.Query

  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.{Repo, Telegram}

  @doc "Queues the « new school » message for `workspace` (inside its create transaction)."
  def new_school(%{id: id}), do: enqueue(%{"event" => "new_school", "workspace_id" => id})

  @doc "Queues the message for an error just stored or back after being resolved."
  def error(%{id: id}, reopened?),
    do: enqueue(%{"event" => "error", "error_id" => id, "reopened" => reopened?})

  defp enqueue(args) do
    if Telegram.configured?() do
      with {:ok, _job} <- args |> new() |> Oban.insert(), do: :ok
    else
      :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Gone when deleted in the meantime: nothing to tell.
    case text(args) do
      nil -> :ok
      text -> Telegram.send_message(text)
    end
  end

  defp text(%{"event" => "new_school", "workspace_id" => id}) do
    SchoolProfile
    |> Ash.Query.filter(workspace_id == ^id)
    |> Ash.Query.load(:workspace)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %SchoolProfile{} = profile} ->
        gettext("Nouvelle école à vérifier : %{name} (%{town})\n%{url}",
          name: profile.workspace.name,
          town: profile.town,
          url: url(~p"/admin/schools/#{id}")
        )

      _ ->
        nil
    end
  end

  defp text(%{"event" => "error", "error_id" => id, "reopened" => reopened?}) do
    case Repo.get(ErrorTracker.Error, id) do
      nil ->
        nil

      error ->
        kind = String.replace_prefix(error.kind, "Elixir.", "")
        source = "#{error.source_function} (#{error.source_line})"
        url = url(~p"/admin/errors/#{error.id}")

        if reopened?,
          do:
            gettext("Erreur revenue : %{kind}\nÀ %{source}\n%{url}",
              kind: kind,
              source: source,
              url: url
            ),
          else:
            gettext("Nouvelle erreur : %{kind}\nÀ %{source}\n%{url}",
              kind: kind,
              source: source,
              url: url
            )
    end
  end
end
