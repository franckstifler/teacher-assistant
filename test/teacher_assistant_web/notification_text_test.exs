defmodule TeacherAssistantWeb.NotificationTextTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.Notification
  alias TeacherAssistantWeb.NotificationText

  defp n(kind, params), do: %Notification{kind: kind, params: params}

  @requested %{
    "teacher" => "Awa Nji",
    "student" => "Nkoulou Brice",
    "class" => "6e A",
    "subject" => "SVT",
    "change" => "08 → 13"
  }

  test "correction requested: who asks, then what" do
    note = n(:correction_requested, @requested)
    assert NotificationText.title(note) == "Awa Nji demande une correction de note"
    assert NotificationText.detail(note) == "Nkoulou Brice · 6e A · SVT · 08 → 13"
  end

  test "a notice stored before the change param shows no dangling separator" do
    note = n(:correction_requested, Map.delete(@requested, "change"))
    assert NotificationText.detail(note) == "Nkoulou Brice · 6e A · SVT"
  end

  test "correction decided" do
    p = %{"student" => "Awa", "assessment" => "Devoir 1", "class" => "3e A"}
    ok = n(:correction_decided, Map.put(p, "decision", "approved"))
    no = n(:correction_decided, Map.put(p, "decision", "refused"))
    assert NotificationText.title(ok) == "Correction acceptée"
    assert NotificationText.title(no) == "Correction refusée"
    assert NotificationText.detail(ok) == "Awa · Devoir 1 · 3e A"
  end

  test "reminders" do
    reminder = n(:entry_reminder, %{"subject" => "Maths", "class" => "3e A", "sequence" => "2"})
    assert NotificationText.title(reminder) == "Saisie en retard"
    assert NotificationText.detail(reminder) == "Maths · 3e A · Séquence 2"

    call = n(:roll_call_reminder, %{"class" => "3e A", "time" => "08:00", "subject" => "Maths"})
    assert NotificationText.title(call) == "Appel non fait"
    assert NotificationText.detail(call) == "3e A · 08:00 · Maths"
  end

  test "the text follows the reader's language" do
    reminder = n(:entry_reminder, %{"subject" => "Maths", "class" => "3e A", "sequence" => "2"})

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
      assert NotificationText.detail(reminder) == "Maths · 3e A · Sequence 2"
    end)
  end

  test "a missing value shows a dash" do
    assert NotificationText.detail(n(:entry_reminder, %{"sequence" => "1"})) ==
             "— · — · Séquence 1"
  end

  test "bulletins published" do
    note =
      n(:bulletins_published, %{
        "class" => "6e A",
        "period" => "Trimestre 1",
        "by" => "Marie Ekotto"
      })

    assert NotificationText.title(note) == "Bulletins Trimestre 1 publiés"
    assert NotificationText.detail(note) == "6e A · par Marie Ekotto"
  end

  test "member joined" do
    note = n(:member_joined, %{"name" => "Grace Ayuk", "roles" => "Enseignant"})
    assert NotificationText.title(note) == "Grace Ayuk a rejoint l'établissement"
    assert NotificationText.detail(note) == "Compte lié · Enseignant"
  end

  test "missed roll calls" do
    morning =
      n(:missed_roll_calls, %{"half" => "morning", "count" => "2", "list" => "6e A, 5e B"})

    assert NotificationText.title(morning) == "2 appels non faits ce matin"
    assert NotificationText.detail(morning) == "6e A, 5e B"

    one = n(:missed_roll_calls, %{"half" => "afternoon", "count" => "1", "list" => "6e A"})
    assert NotificationText.title(one) == "1 appel non fait cet après-midi"
  end

  test "temporary password expired" do
    note =
      n(:temporary_password_expired, %{"name" => "Samuel Fotso", "expired_on" => "07/10/2025"})

    assert NotificationText.title(note) ==
             "Samuel Fotso n'a pas utilisé son mot de passe temporaire"

    assert NotificationText.detail(note) == "Expiré le 07/10/2025"
  end

  test "detail is nil when there is nothing to say" do
    assert NotificationText.detail(n(:missed_roll_calls, %{"half" => "morning", "count" => "1"})) ==
             nil
  end
end
