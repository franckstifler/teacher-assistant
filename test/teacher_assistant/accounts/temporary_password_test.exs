defmodule TeacherAssistant.Accounts.TemporaryPasswordTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.TemporaryPassword

  test "two pronounceable words and four digits" do
    for _ <- 1..200 do
      assert TemporaryPassword.generate() =~
               ~r/\A[bdfgklmnprstvz][aeiou][bdfgklmnprstvz][aeiou]-[bdfgklmnprstvz][aeiou][bdfgklmnprstvz][aeiou]-\d{4}\z/
    end
  end

  test "values differ" do
    values = for _ <- 1..200, do: TemporaryPassword.generate()
    assert length(Enum.uniq(values)) == 200
  end
end
