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

  @doc "« Aujourd'hui · 14:05 », « hier · 09:12 », else « ven. 2 oct. · 16:40 » (school time)."
  def when_text(%{inserted_at: %DateTime{} = at}) do
    local = Reference.now(at)

    "#{Dates.relative(NaiveDateTime.to_date(local), Reference.today())} · " <>
      Calendar.strftime(local, "%H:%M")
  end

  defp join(segments), do: segments |> Enum.reject(&is_nil/1) |> Enum.join(" · ")

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
