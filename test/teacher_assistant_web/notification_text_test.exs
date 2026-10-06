defmodule TeacherAssistantWeb.NotificationTextTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.Notification
  alias TeacherAssistantWeb.NotificationText

  defp n(kind, params), do: %Notification{kind: kind, params: params}

  test "the text follows the reader's language" do
    reminder = n(:entry_reminder, %{"subject" => "Maths", "class" => "3e A", "sequence" => "2"})
    assert NotificationText.text(reminder) == "Saisie en retard : Maths · 3e A · Séquence 2"

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
      assert NotificationText.text(reminder) == "Late mark entry: Maths · 3e A · Sequence 2"

      assert NotificationText.text(
               n(:correction_decided, %{
                 "decision" => "refused",
                 "student" => "Awa",
                 "assessment" => "Devoir 1",
                 "class" => "3e A"
               })
             ) == "Correction refused: Awa · Devoir 1 · 3e A"
    end)
  end

  test "a missing value shows a dash" do
    assert NotificationText.text(n(:entry_reminder, %{"sequence" => "1"})) ==
             "Saisie en retard : — · — · Séquence 1"
  end
end
