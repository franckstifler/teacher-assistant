defmodule TeacherAssistant.Academics.FicheExtractor do
  @moduledoc """
  Extracts column-aligned plain text from a PDF. The concrete implementation is
  swappable via application config so tests don't need poppler installed:

      config :teacher_assistant, :fiche_extractor, TeacherAssistant.FicheExtractorStub
  """

  @callback extract(path :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @spec extract(String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract(path), do: impl().extract(path)

  defp impl, do: Application.get_env(:teacher_assistant, :fiche_extractor, __MODULE__.Pdftotext)

  defmodule Pdftotext do
    @moduledoc "Default extractor: shells out to `pdftotext -layout`."
    @behaviour TeacherAssistant.Academics.FicheExtractor

    @impl true
    def extract(path) do
      case System.cmd("pdftotext", ["-layout", path, "-"], stderr_to_stdout: true) do
        {text, 0} -> {:ok, text}
        {output, _code} -> {:error, output}
      end
    rescue
      e -> {:error, e}
    end
  end
end
