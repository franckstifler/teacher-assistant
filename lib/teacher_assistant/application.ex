defmodule TeacherAssistant.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TeacherAssistantWeb.Telemetry,
      TeacherAssistant.Repo,
      {DNSCluster, query: Application.get_env(:teacher_assistant, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TeacherAssistant.PubSub},
      TeacherAssistantWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :teacher_assistant]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: TeacherAssistant.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TeacherAssistantWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
