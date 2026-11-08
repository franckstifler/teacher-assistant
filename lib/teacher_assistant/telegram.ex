defmodule TeacherAssistant.Telegram do
  @moduledoc """
  Plain-text messages to the operators' Telegram chat: a bot made with @BotFather and
  the chat that wrote to it first. Set in production by `TELEGRAM_BOT_TOKEN` and
  `TELEGRAM_CHAT_ID` (config/runtime.exs, docs/DEPLOY.md); without both, nothing is
  sent (`configured?/0`). Sent from `TeacherAssistant.Workers.TelegramAlert`.
  """

  @doc "Whether a bot token and a chat id are both set."
  def configured?, do: present?(config()[:bot_token]) and present?(config()[:chat_id])

  @doc """
  Sends `text` to the chat. `{:error, reason}` carries Telegram's status and
  description, never the request URL (it holds the bot token).
  """
  def send_message(text) when is_binary(text) do
    config = config()

    [
      base_url: "https://api.telegram.org",
      url: "/bot#{config[:bot_token]}/sendMessage",
      json: %{
        chat_id: config[:chat_id],
        text: text,
        link_preview_options: %{is_disabled: true}
      },
      # Telegram answers within a second. A pooled connection left idle (a day, for the
      # morning digest) can be dead and only time out: then one retry, on a new one.
      receive_timeout: 5_000,
      connect_options: [timeout: 5_000],
      retry: :transient,
      max_retries: 1,
      retry_delay: 200,
      retry_log_level: false
    ]
    |> Keyword.merge(config[:req_options] || [])
    |> Req.post()
    |> case do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {status, description(body)}}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp description(%{"description" => description}), do: description
  defp description(_body), do: nil

  defp present?(value), do: value not in [nil, ""]

  defp config, do: Application.get_env(:teacher_assistant, __MODULE__, [])
end
