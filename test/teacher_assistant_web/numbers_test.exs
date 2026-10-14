defmodule TeacherAssistantWeb.NumbersTest do
  use ExUnit.Case, async: true

  alias TeacherAssistantWeb.Numbers

  setup do
    previous = Gettext.get_locale(TeacherAssistantWeb.Gettext)
    on_exit(fn -> Gettext.put_locale(TeacherAssistantWeb.Gettext, previous) end)
    :ok
  end

  test "French uses a decimal comma and keeps two places for averages" do
    Gettext.put_locale(TeacherAssistantWeb.Gettext, "fr")
    assert Numbers.decimal(Decimal.new("14.2")) == "14,20"
    assert Numbers.decimal(Decimal.new("13.333")) == "13,33"
  end

  test "trim drops trailing zeros, for hours and coefficients" do
    Gettext.put_locale(TeacherAssistantWeb.Gettext, "fr")
    assert Numbers.decimal(Decimal.new("0.9166"), trim: true) == "0,92"
    assert Numbers.decimal(Decimal.new("4.00"), trim: true) == "4"
    assert Numbers.hours(Decimal.new("1.5")) == "1,5 h"
    assert Numbers.decimal(2, trim: true) == "2"
  end

  test "English keeps the point; nil is a dash" do
    Gettext.put_locale(TeacherAssistantWeb.Gettext, "en")
    assert Numbers.decimal(Decimal.new("0.9166"), trim: true) == "0.92"
    assert Numbers.decimal(nil) == "—"
  end
end
