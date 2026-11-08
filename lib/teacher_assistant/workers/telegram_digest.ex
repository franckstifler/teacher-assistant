defmodule TeacherAssistant.Workers.TelegramDigest do
  @moduledoc """
  The operators' morning message on Telegram (07:00 school time, config/config.exs):
  schools waiting to be verified, schools gone quiet or never started, open errors
  and jobs abandoned overnight (`TeacherAssistant.Operator.digest/1`). Sent even
  when there is nothing to handle: it is also the daily sign that the app and its
  alerts are alive. Nothing is sent while Telegram is not set up.
  """
  use Oban.Worker, queue: :default, max_attempts: 3
  use TeacherAssistantWeb, :verified_routes
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.{Operator, Telegram}

  # Schools named per list; the rest are counted.
  @names 5

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Telegram.configured?() do
      now = DateTime.utc_now()
      now |> Operator.digest() |> text(now) |> Telegram.send_message()
    else
      :ok
    end
  end

  @doc false
  def text(digest, now) do
    sections =
      [
        schools(gettext("À vérifier"), digest.pending, &days_since(&1.since, now)),
        schools(
          gettext("Silencieuses depuis 14 jours"),
          digest.quiet,
          &days_since(&1.last_at, now)
        ),
        schools(
          gettext("Vérifiées, jamais utilisées"),
          digest.silent,
          &days_since(&1.since, now)
        ),
        count(gettext("Erreurs ouvertes"), digest.open_errors),
        count(gettext("Tâches abandonnées depuis hier"), digest.failed_jobs)
      ]
      |> Enum.reject(&is_nil/1)

    body = if sections == [], do: [gettext("Rien à traiter.")], else: sections

    Enum.join(
      [gettext("Scolaka · point du matin")] ++ body ++ [url(~p"/admin")],
      "\n\n"
    )
  end

  defp schools(_title, [], _age), do: nil

  defp schools(title, schools, age) do
    lines = for school <- Enum.take(schools, @names), do: "• #{school.name} (#{age.(school)})"

    more =
      case length(schools) - @names do
        n when n > 0 -> [gettext("• et %{count} autres", count: n)]
        _ -> []
      end

    Enum.join(["#{title} : #{length(schools)}" | lines ++ more], "\n")
  end

  defp count(_title, 0), do: nil
  defp count(title, n), do: "#{title} : #{n}"

  defp days_since(at, now) do
    case DateTime.diff(now, at, :day) do
      0 -> gettext("aujourd'hui")
      days -> ngettext("depuis %{count} jour", "depuis %{count} jours", days)
    end
  end
end
