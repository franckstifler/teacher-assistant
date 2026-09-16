defmodule TeacherAssistant.Academics.FicheExtractorTest do
  use ExUnit.Case, async: false
  alias TeacherAssistant.Academics.FicheExtractor

  test "delegates to the configured extractor module" do
    Application.put_env(:teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub)
    Application.put_env(:teacher_assistant, :fiche_extractor_stub_text, "Module Lecon Duree")

    on_exit(fn ->
      Application.delete_env(:teacher_assistant, :fiche_extractor)
      Application.delete_env(:teacher_assistant, :fiche_extractor_stub_text)
    end)

    assert {:ok, "Module Lecon Duree"} = FicheExtractor.extract("ignored.pdf")
  end

  test "Pdftotext impl returns an error tuple when the binary or file is missing" do
    # Use a path that cannot exist; whether pdftotext is installed or not, this
    # must be a graceful {:error, _}, never a raise.
    assert {:error, _} = FicheExtractor.Pdftotext.extract("/nonexistent/definitely-not-here.pdf")
  end
end
