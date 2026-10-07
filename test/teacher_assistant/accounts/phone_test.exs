defmodule TeacherAssistant.Accounts.PhoneTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Phone

  test "accepts the usual ways of writing a Cameroonian number" do
    for input <- [
          "677123456",
          "6 77 12 34 56",
          "6.77.12.34.56",
          "677-12-34-56",
          "+237677123456",
          "+237 6 77 12 34 56",
          "00237677123456",
          "237677123456",
          "222123456"
        ] do
      assert {:ok, "+237" <> rest} = Phone.normalize(input), "rejected #{input}"
      assert String.length(rest) == 9
    end

    assert Phone.normalize("6 77 12 34 56") == {:ok, "+237677123456"}
  end

  test "rejects anything else" do
    for input <- [
          "",
          "67712345",
          "6771234567",
          "577123456",
          "+33612345678",
          "abc",
          nil,
          677_123_456
        ] do
      assert Phone.normalize(input) == {:error, :invalid}, "accepted #{inspect(input)}"
    end
  end

  test "casts through Ash" do
    assert {:ok, "+237677123456"} = Ash.Type.cast_input(Phone, "677 12 34 56", [])
    assert {:ok, nil} = Ash.Type.cast_input(Phone, nil, [])
    assert {:error, _} = Ash.Type.cast_input(Phone, "12", [])
  end

  test "formats for display" do
    assert Phone.format("+237677123456") == "6 77 12 34 56"
  end
end
