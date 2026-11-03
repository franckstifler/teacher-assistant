defmodule TeacherAssistantWeb.DatesTest do
  use ExUnit.Case, async: true

  alias TeacherAssistantWeb.Dates

  describe "countdown/2" do
    test "« J-n » up to the deadline, J-0 on the day" do
      assert Dates.countdown(~D[2026-11-06], ~D[2026-11-03]) == "J-3"
      assert Dates.countdown(~D[2026-11-03], ~D[2026-11-03]) == "J-0"
    end

    test "nil once past or without a deadline" do
      assert Dates.countdown(~D[2026-11-02], ~D[2026-11-03]) == nil
      assert Dates.countdown(nil, ~D[2026-11-03]) == nil
    end
  end
end
