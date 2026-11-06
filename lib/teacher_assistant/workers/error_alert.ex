defmodule TeacherAssistant.Workers.ErrorAlert do
  @moduledoc """
  E-mails the operators (role `:admin`, with an e-mail address) about an error
  ErrorTracker has just stored for the first time, or that came back after being
  resolved. Once per error and state change, not per occurrence: muting an error
  in `/admin/errors` stops its e-mails (`TeacherAssistant.ErrorReporting`).
  """
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600, keys: [:error_id]]
  use TeacherAssistantWeb, :verified_routes

  require Ash.Query

  alias TeacherAssistant.Accounts.{Emails, User}
  alias TeacherAssistant.{Mailer, Repo}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"error_id" => id, "reopened" => reopened?}}) do
    # Gone when pruned, or when the operator deleted it in the meantime.
    case Repo.get(ErrorTracker.Error, id) do
      nil -> :ok
      error -> notify(error, reopened?)
    end
  end

  defp notify(error, reopened?) do
    url = url(~p"/admin/errors/#{error.id}")

    operators()
    |> Enum.map(&(&1 |> Emails.error_alert(error, reopened?, url) |> Mailer.deliver()))
    |> Enum.find(:ok, &match?({:error, _}, &1))
  end

  defp operators do
    User
    |> Ash.Query.filter(role == :admin and not is_nil(email))
    |> Ash.read!(authorize?: false)
  end
end
