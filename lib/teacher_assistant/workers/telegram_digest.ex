defmodule TeacherAssistant.Workers.TelegramDigest do
  @moduledoc """
  The operators' morning message on Telegram (07:00 school time, config/config.exs):
  schools waiting to be verified, schools gone quiet or never started, open errors
  and jobs abandoned overnight, then the schools that took a first step since
  yesterday (`TeacherAssistant.Operator.digest/1`). Sent even
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
      [gettext("Scolaka · point du matin")] ++
        body ++
        List.wrap(swept(Map.get(digest, :swept_files))) ++
        List.wrap(first_steps(digest.first_steps)) ++ [url(~p"/admin")],
      "\n\n"
    )
  end

  # Housekeeping, not something to handle (A9): what the weekly sweep deleted.
  defp swept(n) when is_integer(n) and n > 0,
    do: gettext("Fichiers orphelins supprimés cette semaine : %{n}", n: n)

  defp swept(_n), do: nil

  # Good news, not something to handle: who to call to help them along.
  defp first_steps([]), do: nil

  defp first_steps(schools) do
    lines =
      for school <- Enum.take(schools, @names),
          do: "• #{school.name} : #{Enum.map_join(school.steps, ", ", &step/1)}"

    more =
      case length(schools) - @names do
        n when n > 0 -> [gettext("• et %{count} autres", count: n)]
        _ -> []
      end

    Enum.join(
      ["#{gettext("Premiers pas depuis hier")} : #{length(schools)}" | lines ++ more],
      "\n"
    )
  end

  defp step(:students), do: gettext("élèves inscrits")
  defp step(:roll_call), do: gettext("premier appel")
  defp step(:marks), do: gettext("premières notes")
  defp step(:bulletins), do: gettext("premiers bulletins publiés")

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
