defmodule TeacherAssistant.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    TeacherAssistant.ErrorReporting.attach()

    children = [
      TeacherAssistantWeb.Telemetry,
      TeacherAssistant.Repo,
      TeacherAssistant.Accounts.AccessCache,
      {Oban, Application.fetch_env!(:teacher_assistant, Oban)},
      {DNSCluster, query: Application.get_env(:teacher_assistant, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TeacherAssistant.PubSub},
      {TeacherAssistant.RateLimit, clean_period: :timer.minutes(1)},
      TeacherAssistantWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :teacher_assistant]}
    ]

    with {:ok, _pid} = started <-
           Supervisor.start_link(children,
             strategy: :one_for_one,
             name: TeacherAssistant.Supervisor
           ) do
      # On Telegram, when set up: a deploy is up, or something restarted the app.
      TeacherAssistant.Workers.TelegramAlert.started()
      started
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    TeacherAssistantWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
