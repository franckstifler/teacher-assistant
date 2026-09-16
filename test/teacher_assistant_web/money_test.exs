defmodule TeacherAssistantWeb.MoneyTest do
  use ExUnit.Case, async: true
  alias TeacherAssistantWeb.Money

  test "format_fcfa/1 groups thousands with a space and appends FCFA" do
    assert Money.format_fcfa(25_000) == "25 000 FCFA"
  end

  test "format_fcfa/1 handles 0" do
    assert Money.format_fcfa(0) == "0 FCFA"
  end

  test "format_fcfa/1 handles small values without a separator" do
    assert Money.format_fcfa(500) == "500 FCFA"
  end

  test "format_fcfa/1 handles negatives" do
    assert Money.format_fcfa(-1_000) == "-1 000 FCFA"
  end

  test "format_fcfa/1 handles large values with multiple groups" do
    assert Money.format_fcfa(1_234_567) == "1 234 567 FCFA"
  end
end
