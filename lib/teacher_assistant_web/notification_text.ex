defmodule TeacherAssistantWeb.NotificationText do
  @moduledoc """
  Spec KLM8: a notification's words, built at display time from its `kind` and
  `params`, so they follow the reader's language.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistantWeb.Dates

  def text(%{kind: :correction_requested, params: p}) do
    gettext("%{teacher} demande une correction : %{student} · %{subject} · %{class}",
      teacher: get(p, "teacher"),
      student: get(p, "student"),
      subject: get(p, "subject"),
      class: get(p, "class")
    )
  end

  def text(%{kind: :correction_decided, params: %{"decision" => "approved"} = p}) do
    gettext("Correction approuvée : %{student} · %{assessment} · %{class}",
      student: get(p, "student"),
      assessment: get(p, "assessment"),
      class: get(p, "class")
    )
  end

  def text(%{kind: :correction_decided, params: p}) do
    gettext("Correction refusée : %{student} · %{assessment} · %{class}",
      student: get(p, "student"),
      assessment: get(p, "assessment"),
      class: get(p, "class")
    )
  end

  def text(%{kind: :entry_reminder, params: p}) do
    gettext("Saisie en retard : %{subject} · %{class} · %{sequence}",
      subject: get(p, "subject"),
      class: get(p, "class"),
      sequence: gettext("Séquence %{n}", n: get(p, "sequence"))
    )
  end

  def text(%{kind: :roll_call_reminder, params: p}) do
    gettext("Appel non fait : %{class} · %{time} · %{subject}",
      class: get(p, "class"),
      time: get(p, "time"),
      subject: get(p, "subject")
    )
  end

  @doc "« Aujourd'hui · 14:05 », « hier · 09:12 », else « ven. 2 oct. · 16:40 » (school time)."
  def when_text(%{inserted_at: %DateTime{} = at}) do
    local = Reference.now(at)

    "#{Dates.relative(NaiveDateTime.to_date(local), Reference.today())} · " <>
      Calendar.strftime(local, "%H:%M")
  end

  defp get(params, key) do
    case Map.get(params, key) do
      value when value in [nil, ""] -> "—"
      value -> value
    end
  end
end
