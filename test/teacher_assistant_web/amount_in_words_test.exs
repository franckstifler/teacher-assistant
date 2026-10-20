defmodule TeacherAssistantWeb.AmountInWordsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistantWeb.AmountInWords

  test "French amounts in words" do
    for {n, words} <- [
          {0, "zéro"},
          {1, "un"},
          {16, "seize"},
          {17, "dix-sept"},
          {21, "vingt et un"},
          {32, "trente-deux"},
          {71, "soixante et onze"},
          {77, "soixante-dix-sept"},
          {80, "quatre-vingts"},
          {81, "quatre-vingt-un"},
          {91, "quatre-vingt-onze"},
          {100, "cent"},
          {200, "deux cents"},
          {201, "deux cent un"},
          {1_000, "mille"},
          {2_000, "deux mille"},
          {25_500, "vingt-cinq mille cinq cents"},
          {80_000, "quatre-vingt mille"},
          {200_000, "deux cent mille"},
          {1_000_000, "un million"},
          {2_500_000, "deux millions cinq cent mille"},
          {200_000_000, "deux cents millions"},
          {1_000_000_000, "un milliard"}
        ] do
      assert AmountInWords.fr(n) == words, "#{n}"
    end
  end
end
