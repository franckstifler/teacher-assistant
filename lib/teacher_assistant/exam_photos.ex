defmodule TeacherAssistant.ExamPhotos do
  @moduledoc """
  Spec 2026-10-29: what goes on a candidate's exam picture and in the zip — the exam
  code suggested from the class, the name (shortened when too long), the codes line
  and the file names. Pure rules; the picture itself is drawn in the browser.
  """

  @exam_levels ["1ère", "Terminale"]

  # Observed on the user's school (spec « How »): only a suggestion, the user edits it.
  @prefixes %{
    {"1ère", "F3"} => "PB",
    {"1ère", "F4-BA"} => "PB",
    {"1ère", "CG"} => "PB",
    {"1ère", "AMEB"} => "PT",
    {"1ère", "IH"} => "PT",
    {"1ère", "ESF"} => "PT",
    {"Terminale", "F3"} => "BA",
    {"Terminale", "F4-BA"} => "BA",
    {"Terminale", "AMEB"} => "BT",
    {"Terminale", "IH"} => "BT",
    {"Terminale", "ESF"} => "BT"
  }

  # The surname may be two words, and the app keeps one `full_name`: never shorten them.
  @kept_words 2

  # The school day: Cameroon is UTC+1 all year.
  @utc_offset_seconds 3600

  def exam_levels, do: @exam_levels

  def suggested_exam_code(level, serie) do
    case @prefixes[{level, serie}] do
      nil -> nil
      prefix -> prefix <> serie
    end
  end

  @doc """
  The name in capitals, most complete first: each next variant turns one more word into
  its initial, from the end, never the first two words. The browser picks the first that
  fits on the picture.
  """
  def name_variants(full_name) do
    words = full_name |> String.split() |> Enum.map(&String.upcase/1)
    shortenable = max(length(words) - @kept_words, 0)

    for k <- 0..shortenable do
      {kept, shortened} = Enum.split(words, length(words) - k)
      Enum.join(kept ++ Enum.map(shortened, &initial/1), " ")
    end
  end

  defp initial(word), do: String.first(word) <> "."

  @doc "The second line under the name: « PBF3  CR  8127 » (two spaces between tokens)."
  def codes_line(exam_code, center_code) do
    [exam_code, center_code]
    |> Enum.flat_map(&String.split(&1 || ""))
    |> Enum.map_join("  ", &String.upcase/1)
  end

  @doc "Student id → `<exam code>_<NAME>.jpg`, unique within the list (`_2`, `_3`…)."
  def file_names(exam_code, students) do
    prefix = safe_segment(exam_code || "SANS-CODE")

    {names, _seen} =
      Enum.map_reduce(students, %{}, fn %{id: id, full_name: full_name}, seen ->
        base = prefix <> "_" <> safe_segment(full_name)
        count = Map.get(seen, base, 0) + 1
        name = if count == 1, do: base <> ".jpg", else: "#{base}_#{count}.jpg"
        {{id, name}, Map.put(seen, base, count)}
      end)

    Map.new(names)
  end

  @doc "ASCII capitals, digits, `_` and `-` only: for file and folder names in the zip."
  def safe_segment(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.upcase()
    |> String.split()
    |> Enum.join("_")
    |> String.replace(~r/[^A-Z0-9_-]/, "")
  end

  @doc "The day the photo was taken, as printed on the picture (`dd/mm/yyyy`)."
  def photo_date(nil), do: nil

  def photo_date(%DateTime{} = taken_at),
    do: taken_at |> DateTime.add(@utc_offset_seconds) |> Calendar.strftime("%d/%m/%Y")
end
