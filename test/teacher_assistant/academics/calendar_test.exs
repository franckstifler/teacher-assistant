defmodule TeacherAssistant.Academics.CalendarTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{year: year}
  end

  test "build_default_calendar creates 3 terms and 6 sequences", %{year: year} do
    assert :ok = Organization.build_default_calendar(year)
    seqs = Organization.list_sequences(year)
    assert length(seqs) == 6
    assert Enum.map(seqs, & &1.number) == [1, 2, 3, 4, 5, 6]
  end

  test "current_sequence finds the sequence covering a date", %{year: year} do
    :ok = Organization.build_default_calendar(year)
    seq = Organization.current_sequence(year, ~D[2025-09-20])
    assert seq.number == 1
  end
end

defmodule TeacherAssistant.Academics.CalendarTemplateTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.TeacherFixtures

  defp year_fixture(start_date, end_date) do
    %{workspace: ws} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "#{start_date.year}-#{end_date.year}",
        start_date: start_date,
        end_date: end_date,
        active: true
      })

    year
  end

  test "the preset anchors dates on the year's own start year, not 2025" do
    preset = Reference.default_calendar_preset(~D[2027-09-06], ~D[2028-07-28])
    [t1 | _] = preset.terms
    [s1 | _] = t1.sequences
    assert s1.start_date.year == 2027
    last = preset.terms |> List.last() |> Map.fetch!(:sequences) |> List.last()
    assert last.end_date.year == 2028
  end

  test "build_default_calendar keeps every séquence inside the year" do
    year = year_fixture(~D[2027-09-06], ~D[2028-07-28])
    :ok = Organization.build_default_calendar(year)
    seqs = Organization.list_sequences(year)
    assert length(seqs) == 6

    for s <- seqs do
      assert Date.compare(s.start_date, year.start_date) != :lt
      assert Date.compare(s.end_date, year.end_date) != :gt
      assert Date.compare(s.start_date, s.end_date) == :lt
    end
  end

  test "the first séquence starts on the year's start date and the last ends on its end date" do
    year = year_fixture(~D[2027-09-13], ~D[2028-06-09])
    :ok = Organization.build_default_calendar(year)
    seqs = Organization.list_sequences(year)
    assert List.first(seqs).start_date == ~D[2027-09-13]
    assert List.last(seqs).end_date == ~D[2028-06-09]
  end

  test "the template refuses a span too short for six séquences" do
    assert_raise ArgumentError, fn ->
      Reference.default_calendar_preset(~D[2027-09-06], ~D[2027-09-08])
    end
  end

  test "an academic year whose end precedes its start is rejected" do
    %{workspace: ws} = TeacherFixtures.school_fixture()

    assert {:error, %Ash.Error.Invalid{}} =
             Organization.create_academic_year(ws, %{
               name: "Broken",
               start_date: ~D[2026-09-01],
               end_date: ~D[2025-07-05],
               active: true
             })
  end

  test "build_default_calendar is idempotent" do
    year = year_fixture(~D[2027-09-06], ~D[2028-07-28])
    :ok = Organization.build_default_calendar(year)
    :ok = Organization.build_default_calendar(year)
    assert length(Organization.list_sequences(year)) == 6
  end

  test "a year that starts in January still gets six ordered séquences" do
    year = year_fixture(~D[2027-01-11], ~D[2027-11-26])
    :ok = Organization.build_default_calendar(year)
    seqs = Organization.list_sequences(year)
    assert Enum.map(seqs, & &1.number) == [1, 2, 3, 4, 5, 6]
    starts = Enum.map(seqs, & &1.start_date)
    assert starts == Enum.sort(starts, Date)
    assert List.last(seqs).end_date == ~D[2027-11-26]
  end
end
