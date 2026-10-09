defmodule TeacherAssistantWeb.NotificationText do
  @moduledoc """
  Spec KLM8: a notification's words, built at display time from its `kind` and
  `params`, so they follow the reader's language.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates

  @doc "The first line: what happened."
  def title(%{kind: :correction_requested, params: p}) do
    gettext("%{teacher} demande une correction de note", teacher: get(p, "teacher"))
  end

  def title(%{kind: :correction_decided, params: %{"decision" => "approved"}}),
    do: gettext("Correction acceptée")

  def title(%{kind: :correction_decided}), do: gettext("Correction refusée")
  def title(%{kind: :entry_reminder}), do: gettext("Saisie en retard")
  def title(%{kind: :roll_call_reminder}), do: gettext("Appel non fait")

  def title(%{kind: :bulletins_published, params: p}) do
    gettext("Bulletins %{period} publiés", period: period_label(p))
  end

  def title(%{kind: :member_joined, params: p}) do
    gettext("%{name} a rejoint l'établissement", name: get(p, "name"))
  end

  def title(%{kind: :missed_roll_calls, params: p}) do
    count = count(p)

    case Map.get(p, "half") do
      "afternoon" ->
        ngettext(
          "%{count} appel non fait cet après-midi",
          "%{count} appels non faits cet après-midi",
          count
        )

      _ ->
        ngettext("%{count} appel non fait ce matin", "%{count} appels non faits ce matin", count)
    end
  end

  def title(%{kind: :temporary_password_expired, params: p}) do
    gettext("%{name} n'a pas utilisé son mot de passe temporaire", name: get(p, "name"))
  end

  @doc "The second line: about whom and what; nil when there is nothing more to say."
  def detail(%{kind: :correction_requested, params: p}) do
    join([get(p, "student"), get(p, "class"), get(p, "subject"), present(p, "change")])
  end

  def detail(%{kind: :correction_decided, params: p}) do
    join([get(p, "student"), get(p, "assessment"), get(p, "class")])
  end

  def detail(%{kind: :entry_reminder, params: p}) do
    join([
      get(p, "subject"),
      get(p, "class"),
      gettext("Séquence %{n}", n: get(p, "sequence"))
    ])
  end

  def detail(%{kind: :roll_call_reminder, params: p}) do
    join([get(p, "class"), get(p, "time"), get(p, "subject")])
  end

  def detail(%{kind: :bulletins_published, params: p}) do
    join([present(p, "class"), by_text(p)])
  end

  def detail(%{kind: :member_joined, params: p}) do
    join([gettext("Compte lié"), role_labels(p)])
  end

  def detail(%{kind: :missed_roll_calls, params: p}), do: join([present(p, "list")])

  def detail(%{kind: :temporary_password_expired, params: p}) do
    case present(p, "expired_on") do
      nil -> nil
      date -> gettext("Expiré le %{date}", date: date)
    end
  end

  @doc "« Aujourd'hui · 14:05 », « hier · 09:12 », else « ven. 2 oct. · 16:40 » (school time)."
  def when_text(%{inserted_at: %DateTime{} = at}) do
    local = Reference.now(at)

    "#{Dates.relative(NaiveDateTime.to_date(local), Reference.today())} · " <>
      Calendar.strftime(local, "%H:%M")
  end

  # nil when no segment is present, so callers can `:if` on the result.
  defp join(segments) do
    case Enum.reject(segments, &is_nil/1) do
      [] -> nil
      present -> Enum.join(present, " · ")
    end
  end

  # Built at display time so it follows the reader's language.
  defp period_label(%{"period_kind" => "annual"}), do: gettext("Année")

  defp period_label(%{"period_kind" => "trimester", "position" => n}),
    do: gettext("Trimestre %{n}", n: n)

  defp period_label(_), do: "—"

  defp by_text(params) do
    case present(params, "by") do
      nil -> nil
      by -> gettext("par %{name}", name: by)
    end
  end

  defp count(params) do
    case Integer.parse(to_string(Map.get(params, "count"))) do
      {n, _} -> n
      :error -> 0
    end
  end

  # Roles are stored as values ("teacher,head") and translated at display time; an old
  # notice that stored a label keeps showing it.
  defp role_labels(params) do
    case present(params, "roles") do
      nil ->
        nil

      roles ->
        roles
        |> String.split(",", trim: true)
        |> Enum.map_join(", ", fn role ->
          case Enum.find(TeacherAssistant.Accounts.SchoolRole.values(), &(to_string(&1) == role)) do
            nil -> role
            value -> TeacherAssistant.Accounts.SchoolRole.label(value)
          end
        end)
    end
  end

  defp present(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> nil
      value -> value
    end
  end

  defp get(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> "—"
      value -> value
    end
  end
end
