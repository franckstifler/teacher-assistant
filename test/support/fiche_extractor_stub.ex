defmodule TeacherAssistant.FicheExtractorStub do
  @moduledoc "Test extractor: returns text from application env, ignoring the path."
  @behaviour TeacherAssistant.Academics.FicheExtractor

  @impl true
  def extract(_path) do
    case Application.get_env(:teacher_assistant, :fiche_extractor_stub_text) do
      nil -> {:error, :no_stub_text}
      text -> {:ok, text}
    end
  end
end
