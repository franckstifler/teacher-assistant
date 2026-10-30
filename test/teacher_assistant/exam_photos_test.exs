defmodule TeacherAssistant.ExamPhotosTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.ExamPhotos

  test "suggested_exam_code/2 follows the series table" do
    assert ExamPhotos.suggested_exam_code("1ère", "F3") == "PBF3"
    assert ExamPhotos.suggested_exam_code("1ère", "F4-BA") == "PBF4-BA"
    assert ExamPhotos.suggested_exam_code("1ère", "CG") == "PBCG"
    assert ExamPhotos.suggested_exam_code("1ère", "AMEB") == "PTAMEB"
    assert ExamPhotos.suggested_exam_code("1ère", "IH") == "PTIH"
    assert ExamPhotos.suggested_exam_code("1ère", "ESF") == "PTESF"
    assert ExamPhotos.suggested_exam_code("Terminale", "F3") == "BAF3"
    assert ExamPhotos.suggested_exam_code("Terminale", "F4-BA") == "BAF4-BA"
    assert ExamPhotos.suggested_exam_code("Terminale", "AMEB") == "BTAMEB"
    assert ExamPhotos.suggested_exam_code("Terminale", "IH") == "BTIH"
    assert ExamPhotos.suggested_exam_code("Terminale", "ESF") == "BTESF"
    assert ExamPhotos.suggested_exam_code("Terminale", "CG") == nil
    assert ExamPhotos.suggested_exam_code("2nde", "F3") == nil
    assert ExamPhotos.suggested_exam_code("1ère", nil) == nil
  end

  test "name_variants/1 shortens from the end, never the first two words" do
    assert ExamPhotos.name_variants("Biyong Ndjeng Emmanuel Patrice") == [
             "BIYONG NDJENG EMMANUEL PATRICE",
             "BIYONG NDJENG EMMANUEL P.",
             "BIYONG NDJENG E. P."
           ]

    assert ExamPhotos.name_variants("  Ateba   Ben ") == ["ATEBA BEN"]

    assert ExamPhotos.name_variants("Hervé N'Diaye-Ékollo Zoé") ==
             ["HERVÉ N'DIAYE-ÉKOLLO ZOÉ", "HERVÉ N'DIAYE-ÉKOLLO Z."]
  end

  test "codes_line/2 joins every token with two spaces" do
    assert ExamPhotos.codes_line("PBF3", " cr  8127 ") == "PBF3  CR  8127"
    assert ExamPhotos.codes_line(nil, "CR 8127") == "CR  8127"
    assert ExamPhotos.codes_line("PBF3", nil) == "PBF3"
    assert ExamPhotos.codes_line(nil, nil) == ""
  end

  test "file_names/2 is ASCII, capitalised and deduplicates" do
    students = [
      %{id: "a", full_name: "Hervé N'Diaye-Ékollo"},
      %{id: "b", full_name: "Ngono Jean"},
      %{id: "c", full_name: "Ngono  Jean"}
    ]

    assert ExamPhotos.file_names("PBF4-BA", students) == %{
             "a" => "PBF4-BA_HERVE_NDIAYE-EKOLLO.jpg",
             "b" => "PBF4-BA_NGONO_JEAN.jpg",
             "c" => "PBF4-BA_NGONO_JEAN_2.jpg"
           }
  end

  test "file_names/2 without an exam code" do
    assert ExamPhotos.file_names(nil, [%{id: "a", full_name: "Ngono Jean"}]) ==
             %{"a" => "SANS-CODE_NGONO_JEAN.jpg"}
  end

  test "photo_date/1 is the Douala day" do
    assert ExamPhotos.photo_date(~U[2025-11-23 22:59:00Z]) == "23/11/2025"
    assert ExamPhotos.photo_date(~U[2025-11-23 23:30:00Z]) == "24/11/2025"
    assert ExamPhotos.photo_date(nil) == nil
  end
end
