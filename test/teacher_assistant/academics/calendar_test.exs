defmodule TeacherAssistant.Academics.CalendarTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{year: year}
  end

  test "build_default_calendar creates 3 terms and 6 sequences", %{year: year} do
    assert :ok = Academics.build_default_calendar(year)
    seqs = Academics.list_sequences(year)
    assert length(seqs) == 6
    assert Enum.map(seqs, & &1.number) == [1, 2, 3, 4, 5, 6]
  end

  test "current_sequence finds the sequence covering a date", %{year: year} do
    :ok = Academics.build_default_calendar(year)
    seq = Academics.current_sequence(year, ~D[2025-09-20])
    assert seq.number == 1
  end
end
