defmodule TeacherAssistant.Academics.FicheParserTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.FicheParser

  # Columns are space-aligned, as produced by `pdftotext -layout`.
  @fr_tabular """
  FICHE DE PROGRESSION - Mathematiques 6eme

  Module                 Lecon                      Duree
  Nombres et calculs     Les entiers naturels       2
  Nombres et calculs     Addition et soustraction   3
  Geometrie              Les droites                 1
  """

  test "parses a clean tabular fiche into module/lesson/hours rows" do
    assert {:ok, %{rows: rows, confidence: :high}} = FicheParser.parse(@fr_tabular)
    assert length(rows) == 3

    assert %{
             module: "Nombres et calculs",
             lesson_title: "Les entiers naturels",
             planned_hours: hours,
             entry_type: :lesson,
             week_no: nil,
             sequence_no: nil
           } = hd(rows)

    assert Decimal.equal?(hours, Decimal.new("2"))
  end

  test "carries the module forward when the module cell is blank" do
    text = """
    Module             Lecon                  Duree
    Algebre            Identites remarquables 2
                       Factorisation          2
    """

    assert {:ok, %{rows: [r1, r2]}} = FicheParser.parse(text)
    assert r1.module == "Algebre"
    assert r2.module == "Algebre"
    assert r2.lesson_title == "Factorisation"
  end

  test "defaults planned_hours to 1 when the duration is missing or unparseable" do
    text = """
    Module     Lecon              Duree
    Intro      Presentation       --
    """

    assert {:ok, %{rows: [row]}} = FicheParser.parse(text)
    assert Decimal.equal?(row.planned_hours, Decimal.new("1"))
  end

  test "returns low confidence and empty rows when no header is found" do
    assert {:ok, %{rows: [], confidence: :low, raw_text: raw}} =
             FicheParser.parse("just some prose with no table at all\nsecond line")

    assert raw =~ "just some prose"
  end

  test "never raises on garbage input" do
    assert {:ok, %{confidence: :low}} = FicheParser.parse("")
  end

  test "correctly parses accented French headers (Leçon, Durée, Thème)" do
    # Regression: byte offsets from Regex.run must be converted to char offsets
    # before using with String.slice. Accented chars (multi-byte UTF-8) would shift
    # later columns if offsets weren't converted.
    text = """
    Module                 Leçon                      Durée
    Nombres et calculs     Les entiers naturels       2
    Nombres et calculs     Addition et soustraction   3
    Géométrie              Les droites                1
    """

    assert {:ok, %{rows: rows, confidence: :high}} = FicheParser.parse(text)
    assert length(rows) == 3

    # First row: check module, lesson, and hours are correct
    assert %{
             module: "Nombres et calculs",
             lesson_title: "Les entiers naturels",
             planned_hours: hours
           } = hd(rows)

    assert Decimal.equal?(hours, Decimal.new("2"))

    # Third row: check "Géométrie" with accented character is parsed correctly
    assert %{
             module: "Géométrie",
             lesson_title: "Les droites",
             planned_hours: hours3
           } = Enum.at(rows, 2)

    assert Decimal.equal?(hours3, Decimal.new("1"))
  end
end
