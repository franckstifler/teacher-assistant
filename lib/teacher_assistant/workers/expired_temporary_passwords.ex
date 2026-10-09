defmodule TeacherAssistant.Workers.ExpiredTemporaryPasswords do
  @moduledoc """
  Pilotage redesign §1.3: tells the school's admins about each member whose
  temporary password expired in the last 24 hours without ever being used
  (`must_change_password` still true). The 24 h window and the daily run make
  each account reported once.
  """
  use Oban.Worker, queue: :default, max_attempts: 2, unique: [period: 3600]

  require Logger

  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.{User, Workspaces}
  alias TeacherAssistant.{Notifications, Scope}

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    since = DateTime.add(now, -24, :hour)

    run(Workspaces.job_scopes(), &notify(&1, since, now))
  end

  @doc false
  # One school failing is logged and skipped: it must not stop the schools after it.
  def run(scopes, fun) do
    for scope <- scopes, Scope.school_verified?(scope) do
      try do
        fun.(scope)
      rescue
        error ->
          Logger.warning(
            "expired temporary passwords failed for workspace #{scope.current_workspace.id}: " <>
              Exception.message(error)
          )
      end
    end

    :ok
  end

  defp notify(scope, since, now) do
    admins = Notifications.admin_ids(scope)

    for %{user: user} <- Accounts.list_members(scope), expired?(user, since, now) do
      Notifications.deliver(
        scope,
        :temporary_password_expired,
        admins,
        %{
          name: User.display_name(user),
          expired_on: user.temporary_password_expires_at |> Reference.today() |> format()
        },
        "/school/members"
      )
    end
  end

  defp expired?(
         %{must_change_password: true, temporary_password_expires_at: %DateTime{} = at},
         since,
         now
       ),
       do: DateTime.compare(at, since) != :lt and DateTime.compare(at, now) != :gt

  defp expired?(_user, _since, _now), do: false

  defp format(date), do: Calendar.strftime(date, "%d/%m/%Y")
end
