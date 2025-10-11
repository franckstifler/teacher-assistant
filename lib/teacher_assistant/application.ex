defmodule TeacherAssistant.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TeacherAssistantWeb.Telemetry,
      TeacherAssistant.Repo,
      {DNSCluster, query: Application.get_env(:teacher_assistant, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:teacher_assistant, :ash_domains),
         Application.fetch_env!(:teacher_assistant, Oban)
       )},
      {Phoenix.PubSub, name: TeacherAssistant.PubSub},
      # Start a worker by calling: TeacherAssistant.Worker.start_link(arg)
      # {TeacherAssistant.Worker, arg},
      # Start to serve requests, typically the last entry
      TeacherAssistantWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :teacher_assistant]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TeacherAssistant.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TeacherAssistantWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
