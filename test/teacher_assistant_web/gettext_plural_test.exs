defmodule TeacherAssistantWeb.GettextPluralTest do
  @moduledoc """
  The French source strings leave many msgstr empty, so plural messages fall back to the
  msgid/msgid_plural pair. The singular must follow the locale's rule: French treats 0 as
  singular, English does not.
  """
  use ExUnit.Case, async: true
  use Gettext, backend: TeacherAssistantWeb.Gettext

  defp count_text(n),
    do: ngettext("%{count} gizmo en attente", "%{count} gizmos en attente", n)

  test "French (untranslated plural) uses the singular for 0 and 1" do
    Gettext.with_locale(TeacherAssistantWeb.Gettext, "fr", fn ->
      assert count_text(0) == "0 gizmo en attente"
      assert count_text(1) == "1 gizmo en attente"
      assert count_text(2) == "2 gizmos en attente"
    end)
  end

  test "English uses the plural for 0" do
    Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
      assert count_text(0) == "0 gizmos en attente"
      assert count_text(1) == "1 gizmo en attente"
    end)
  end

  test "French translated plural entries also use the singular for 0" do
    Gettext.with_locale(TeacherAssistantWeb.Gettext, "fr", fn ->
      assert ngettext("%{count} classe", "%{count} classes", 0) == "0 classe"
    end)
  end
end
